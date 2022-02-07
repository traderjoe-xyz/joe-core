// @ts-nocheck
const { ethers, network } = require("hardhat");
const { expect } = require("chai");
const { describe } = require("mocha");
const hre = require("hardhat");

describe("Stable Joe Staking", function () {
  before(async function () {
    this.StableJoeStakingCF = await ethers.getContractFactory(
      "StableJoeStaking"
    );
    this.JoeTokenCF = await ethers.getContractFactory("JoeToken");

    this.signers = await ethers.getSigners();
    this.dev = this.signers[0];
    this.alice = this.signers[1];
    this.bob = this.signers[2];
    this.carol = this.signers[3];
    this.joeMaker = this.signers[4];
    this.penaltyCollector = this.signers[5];
  });

  beforeEach(async function () {
    this.rewardToken = await this.JoeTokenCF.deploy();
    this.joe = await this.JoeTokenCF.deploy();

    await this.joe.mint(this.alice.address, ethers.utils.parseEther("1000"));
    await this.joe.mint(this.bob.address, ethers.utils.parseEther("1000"));
    await this.joe.mint(this.carol.address, ethers.utils.parseEther("1000"));
    await this.rewardToken.mint(
      this.joeMaker.address,
      ethers.utils.parseEther("1000000")
    ); // 1_000_000 tokens

    this.stableJoeStaking = await hre.upgrades.deployProxy(
      this.StableJoeStakingCF,
      [
        this.rewardToken.address,
        this.joe.address,
        this.penaltyCollector.address,
        ethers.utils.parseEther("0.03"),
      ]
    );

    await this.joe
      .connect(this.alice)
      .approve(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("100000")
      );
    await this.joe
      .connect(this.bob)
      .approve(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("100000")
      );
    await this.joe
      .connect(this.carol)
      .approve(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("100000")
      );
  });

  describe("should allow deposits and withdraws", function () {
    it("should allow deposits and withdraws of multiple users", async function () {
      await this.stableJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("900")
      );
      expect(
        await this.joe.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(ethers.utils.parseEther("97"));
      // 100 * 0.97 = 97
      expect(
        (
          await this.stableJoeStaking.getUserInfo(
            this.alice.address,
            this.joe.address
          )
        )[0]
      ).to.be.equal(ethers.utils.parseEther("97"));

      await this.stableJoeStaking
        .connect(this.bob)
        .deposit(ethers.utils.parseEther("200"));
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(
        ethers.utils.parseEther("800")
        // 97 + 200 * 0.97 = 291
      );
      expect(
        await this.joe.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(ethers.utils.parseEther("291"));
      expect(
        (
          await this.stableJoeStaking.getUserInfo(
            this.bob.address,
            this.joe.address
          )
        )[0]
      ).to.be.equal(ethers.utils.parseEther("194"));

      await this.stableJoeStaking
        .connect(this.carol)
        .deposit(ethers.utils.parseEther("300"));
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(
        ethers.utils.parseEther("700")
      );
      // 291 + 300 * 0.97
      expect(
        await this.joe.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(ethers.utils.parseEther("582"));
      expect(
        (
          await this.stableJoeStaking.getUserInfo(
            this.carol.address,
            this.joe.address
          )
        )[0]
      ).to.be.equal(ethers.utils.parseEther("291"));

      await this.stableJoeStaking
        .connect(this.alice)
        .withdraw(ethers.utils.parseEther("97"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("997")
      );
      expect(
        await this.joe.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(ethers.utils.parseEther("485"));
      expect(
        (
          await this.stableJoeStaking.getUserInfo(
            this.alice.address,
            this.joe.address
          )
        )[0]
      ).to.be.equal(0);

      await this.stableJoeStaking
        .connect(this.carol)
        .withdraw(ethers.utils.parseEther("100"));
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(
        ethers.utils.parseEther("800")
      );
      expect(
        await this.joe.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(ethers.utils.parseEther("385"));
      expect(
        (
          await this.stableJoeStaking.getUserInfo(
            this.carol.address,
            this.joe.address
          )
        )[0]
      ).to.be.equal(ethers.utils.parseEther("191"));

      await this.stableJoeStaking.connect(this.bob).withdraw("1");
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(
        ethers.utils.parseEther("800.000000000000000001")
      );
      expect(
        await this.joe.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(ethers.utils.parseEther("384.999999999999999999"));
      expect(
        (
          await this.stableJoeStaking.getUserInfo(
            this.bob.address,
            this.joe.address
          )
        )[0]
      ).to.be.equal(ethers.utils.parseEther("193.999999999999999999"));
    });

    it("should update variables accordingly", async function () {
      await this.stableJoeStaking.connect(this.alice).deposit("1");

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.stableJoeStaking.address, ethers.utils.parseEther("1"));
      expect(
        await this.rewardToken.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(ethers.utils.parseEther("1"));
      expect(
        await this.stableJoeStaking.lastRewardBalance(this.rewardToken.address)
      ).to.be.equal("0");

      await increase(86400);
      expect(
        await this.stableJoeStaking.pendingReward(
          this.alice.address,
          this.rewardToken.address
        )
      ).to.be.equal(ethers.utils.parseEther("1"));

      // Making sure that `pendingReward` still return the accurate tokens even after updating pools
      await this.stableJoeStaking.updateReward(this.rewardToken.address);
      expect(
        await this.stableJoeStaking.pendingReward(
          this.alice.address,
          this.rewardToken.address
        )
      ).to.be.equal(ethers.utils.parseEther("1"));

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.stableJoeStaking.address, ethers.utils.parseEther("1"));
      await increase(86400);

      // Should be equal to 2, the previous reward and the new one
      expect(
        await this.stableJoeStaking.pendingReward(
          this.alice.address,
          this.rewardToken.address
        )
      ).to.be.equal(ethers.utils.parseEther("2"));

      // Making sure that `pendingReward` still return the accurate tokens even after updating pools
      await this.stableJoeStaking.updateReward(this.rewardToken.address);
      expect(
        await this.stableJoeStaking.pendingReward(
          this.alice.address,
          this.rewardToken.address
        )
      ).to.be.equal(ethers.utils.parseEther("2"));
    });

    it("should allow deposits and withdraws of multiple users and distribute rewards accordingly", async function () {
      await this.stableJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));
      await this.stableJoeStaking
        .connect(this.bob)
        .deposit(ethers.utils.parseEther("200"));
      await this.stableJoeStaking
        .connect(this.carol)
        .deposit(ethers.utils.parseEther("300"));

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.stableJoeStaking.address, ethers.utils.parseEther("6"));
      await this.stableJoeStaking.updateReward(this.rewardToken.address);
      await increase(86400);

      await this.stableJoeStaking
        .connect(this.alice)
        .withdraw(ethers.utils.parseEther("97"));
      // accRewardBalance = rewardBalance * PRECISION / totalStaked
      //                  = 6e18 * 1e24 / 582e18
      //                  = 0.010309278350515463917525e24
      // reward = accRewardBalance * aliceShare / PRECISION
      //        = accRewardBalance * 97e18 / 1e24
      //        = 0.999999999999999999e18
      expect(
        await this.rewardToken.balanceOf(this.alice.address)
      ).to.be.closeTo(
        ethers.utils.parseEther("1"),
        ethers.utils.parseEther("0.0001")
      );

      await this.stableJoeStaking
        .connect(this.carol)
        .withdraw(ethers.utils.parseEther("100"));
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(
        ethers.utils.parseEther("800")
      );
      // reward = accRewardBalance * carolShare / PRECISION
      //        = accRewardBalance * 291e18 / 1e24
      //        = 2.999999999999999999e18
      expect(
        await this.rewardToken.balanceOf(this.carol.address)
      ).to.be.closeTo(
        ethers.utils.parseEther("3"),
        ethers.utils.parseEther("0.0001")
      );

      await this.stableJoeStaking.connect(this.bob).withdraw("0");
      // reward = accRewardBalance * carolShare / PRECISION
      //        = accRewardBalance * 194e18 / 1e24
      //        = 1.999999999999999999e18
      expect(await this.rewardToken.balanceOf(this.bob.address)).to.be.closeTo(
        ethers.utils.parseEther("2"),
        ethers.utils.parseEther("0.0001")
      );
    });

    it("should distribute token accordingly even if update isn't called every day", async function () {
      await this.stableJoeStaking.connect(this.alice).deposit(1);
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        0
      );

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.stableJoeStaking.address, ethers.utils.parseEther("1"));
      await increase(86400);
      await this.stableJoeStaking.connect(this.alice).withdraw(0);

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.stableJoeStaking.address, ethers.utils.parseEther("1"));
      await increase(10 * 86400);
      await this.stableJoeStaking.connect(this.alice).withdraw(0);
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("2")
      );
    });

    it("should allow deposits and withdraws of multiple users and distribute rewards accordingly even if someone enters or leaves", async function () {
      await this.stableJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));
      await this.stableJoeStaking
        .connect(this.carol)
        .deposit(ethers.utils.parseEther("100"));

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.stableJoeStaking.address, ethers.utils.parseEther("4"));
      await increase(86400);

      // accRewardBalance = rewardBalance * PRECISION / totalStaked
      //                  = 4e18 * 1e24 / 97e18
      //                  = 0.020618556701030927835051e24
      // bobRewardDebt = accRewardBalance * bobShare / PRECISION
      //               = accRewardBalance * 194e18 / 1e24
      //               = 0.3999999999999999999e18
      await this.stableJoeStaking
        .connect(this.bob)
        .deposit(ethers.utils.parseEther("200")); // Bob enters

      await this.stableJoeStaking
        .connect(this.carol)
        .withdraw(ethers.utils.parseEther("97"));
      // reward = accRewardBalance * carolShare / PRECISION
      //        = accRewardBalance * 97e18 / 1e24
      //        = 1.999999999999999999e18
      expect(
        await this.rewardToken.balanceOf(this.carol.address)
      ).to.be.closeTo(
        ethers.utils.parseEther("2"),
        ethers.utils.parseEther("0.0001")
      );

      await this.stableJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100")); // Alice enters again to try to get more rewards
      await this.stableJoeStaking
        .connect(this.alice)
        .withdraw(ethers.utils.parseEther("194"));
      // She gets the same reward as Carol
      const aliceBalance = await this.rewardToken.balanceOf(this.alice.address);
      // aliceRewardDebt = accRewardBalance * aliceShare / PRECISION
      //        = accRewardBalance * 0 / PRECISION - 0
      //        = 0      (she withdraw everything, so her share is 0)
      // reward = accRewardBalance * aliceShare / PRECISION
      //        = accRewardBalance * 97e18 / 1e24
      //        = 1.999999999999999999e18
      expect(aliceBalance).to.be.closeTo(
        ethers.utils.parseEther("2"),
        ethers.utils.parseEther("0.0001")
      );

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.stableJoeStaking.address, ethers.utils.parseEther("4"));
      await increase(86400);

      await this.stableJoeStaking.connect(this.bob).withdraw("0");
      // reward = accRewardBalance * bobShare / PRECISION - bobRewardDebt
      //        = accRewardBalance * 194e18 / 1e24 - 3.999999999999999999e18
      //        = 4e18
      expect(await this.rewardToken.balanceOf(this.bob.address)).to.be.closeTo(
        ethers.utils.parseEther("4"),
        ethers.utils.parseEther("0.0001")
      );

      // Alice shouldn't receive any token of the last reward
      await this.stableJoeStaking.connect(this.alice).withdraw("0");
      // reward = accRewardBalance * aliceShare / PRECISION - aliceRewardDebt
      //        = accRewardBalance * 0 / PRECISION - 0
      //        = 0      (she withdraw everything, so her share is 0)
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        aliceBalance
      );
    });

    it("pending tokens function should return the same number of token that user actually receive", async function () {
      await this.stableJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("300"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("700")
      );
      expect(
        await this.joe.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(ethers.utils.parseEther("291"));

      await this.rewardToken.mint(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("100")
      ); // We send 100 Tokens to sJoe's address

      const pendingReward = await this.stableJoeStaking.pendingReward(
        this.alice.address,
        this.rewardToken.address
      );
      await this.stableJoeStaking.connect(this.alice).withdraw("0"); // Alice shouldn't receive any token of the last reward
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("700")
      );
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        pendingReward
      );
      expect(
        await this.joe.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(ethers.utils.parseEther("291"));
    });

    it("should allow rewards in JOE and USDC", async function () {
      await this.stableJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("1000"));
      await this.stableJoeStaking
        .connect(this.bob)
        .deposit(ethers.utils.parseEther("1000"));
      await this.stableJoeStaking
        .connect(this.carol)
        .deposit(ethers.utils.parseEther("1000"));

      await this.rewardToken.mint(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("3")
      );

      await this.stableJoeStaking.connect(this.alice).withdraw(0);
      // accRewardBalance = rewardBalance * PRECISION / totalStaked
      //                  = 3e18 * 1e24 / 291e18
      //                  = 0.001030927835051546391752e24
      // reward = accRewardBalance * aliceShare / PRECISION
      //        = accRewardBalance * 970e18 / 1e24
      //        = 0.999999999999999999e18
      // aliceRewardDebt = 0.999999999999999999e18
      const aliceRewardbalance = await this.rewardToken.balanceOf(
        this.alice.address
      );
      expect(aliceRewardbalance).to.be.closeTo(
        ethers.utils.parseEther("1"),
        ethers.utils.parseEther("0.0001")
      );
      // accJoeBalance = 0
      // reward = 0
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(0);

      await this.stableJoeStaking.addRewardToken(this.joe.address);
      await this.joe.mint(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("6")
      );

      await this.stableJoeStaking
        .connect(this.bob)
        .connect(this.bob)
        .withdraw(0);
      // reward = accRewardBalance * bobShare / PRECISION
      //        = accRewardBalance * 970e18 / 1e24
      //        = 0.999999999999999999e18
      expect(await this.rewardToken.balanceOf(this.bob.address)).to.be.closeTo(
        ethers.utils.parseEther("1"),
        ethers.utils.parseEther("0.0001")
      );
      // accJoeBalance = joeBalance * PRECISION / totalStaked
      //                  = 6e18 * 1e24 / 291e18
      //                  = 0.002061855670103092783505e24
      // reward = accJoeBalance * aliceShare / PRECISION
      //        = accJoeBalance * 970e18 / 1e24
      //        = 1.999999999999999999e18
      expect(await this.joe.balanceOf(this.bob.address)).to.be.closeTo(
        ethers.utils.parseEther("2"),
        ethers.utils.parseEther("0.0001")
      );

      await this.stableJoeStaking
        .connect(this.alice)
        .withdraw(ethers.utils.parseEther("0"));
      // reward = accRewardBalance * aliceShare / PRECISION - aliceRewardDebt
      //        = accRewardBalance * 970e18 / 1e24 - 0.999999999999999999e18
      //        = 0
      // so she has the same balance as previously
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        aliceRewardbalance
      );
      // reward = accJoeBalance * aliceShare / PRECISION
      //        = accJoeBalance * 970e18 / 1e24
      //        = 1.999999999999999999e18
      expect(await this.joe.balanceOf(this.alice.address)).to.be.closeTo(
        ethers.utils.parseEther("2"),
        ethers.utils.parseEther("0.0001")
      );
    });

    it("rewardDebt should be updated as expected, alice deposits before last reward is sent", async function () {
      let token1 = await this.JoeTokenCF.deploy();
      await this.stableJoeStaking.addRewardToken(token1.address);

      await this.stableJoeStaking.connect(this.alice).deposit(1);
      await this.stableJoeStaking.connect(this.bob).deposit(1);

      await token1.mint(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("1")
      );
      await this.stableJoeStaking.connect(this.alice).withdraw(1);

      let balAlice = await token1.balanceOf(this.alice.address);
      let balBob = await token1.balanceOf(this.bob.address);
      expect(balAlice).to.be.equal(ethers.utils.parseEther("0.5"));
      expect(balBob).to.be.equal(0);

      await token1.mint(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("1")
      );
      await this.stableJoeStaking.connect(this.bob).withdraw(0);
      await this.stableJoeStaking.connect(this.alice).deposit(1);

      balBob = await token1.balanceOf(this.bob.address);
      expect(await token1.balanceOf(this.alice.address)).to.be.equal(balAlice);
      expect(balBob).to.be.equal(ethers.utils.parseEther("1.5"));

      await token1.mint(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("1")
      );
      await this.stableJoeStaking.connect(this.bob).withdraw(0);
      await this.stableJoeStaking.connect(this.alice).withdraw(0);

      balAlice = await token1.balanceOf(this.alice.address);
      balBob = await token1.balanceOf(this.bob.address);
      expect(await token1.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("1")
      );
      expect(balBob).to.be.equal(ethers.utils.parseEther("2"));

      await this.stableJoeStaking.removeRewardToken(token1.address);
    });

    it("rewardDebt should be updated as expected, alice deposits after last reward is sent", async function () {
      let token1 = await this.JoeTokenCF.deploy();
      await this.stableJoeStaking.addRewardToken(token1.address);

      await this.stableJoeStaking.connect(this.alice).deposit(1);
      await this.stableJoeStaking.connect(this.bob).deposit(1);

      await token1.mint(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("1")
      );
      await this.stableJoeStaking.connect(this.alice).withdraw(1);

      let balAlice = await token1.balanceOf(this.alice.address);
      let balBob = await token1.balanceOf(this.bob.address);
      expect(balAlice).to.be.equal(ethers.utils.parseEther("0.5"));
      expect(balBob).to.be.equal(0);

      await token1.mint(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("1")
      );
      await this.stableJoeStaking.connect(this.bob).withdraw(0);

      balBob = await token1.balanceOf(this.bob.address);
      expect(await token1.balanceOf(this.alice.address)).to.be.equal(balAlice);
      expect(balBob).to.be.equal(ethers.utils.parseEther("1.5"));

      await token1.mint(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("1")
      );
      await this.stableJoeStaking.connect(this.alice).deposit(1);
      await this.stableJoeStaking.connect(this.bob).withdraw(0);
      await this.stableJoeStaking.connect(this.alice).withdraw(0);

      balAlice = await token1.balanceOf(this.alice.address);
      balBob = await token1.balanceOf(this.bob.address);
      expect(await token1.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("0.5")
      );
      expect(balBob).to.be.equal(ethers.utils.parseEther("2.5"));
    });

    it("should allow adding and removing a rewardToken, only by owner", async function () {
      let token1 = await this.JoeTokenCF.deploy();
      await expect(
        this.stableJoeStaking.connect(this.alice).addRewardToken(token1.address)
      ).to.be.revertedWith("Ownable: caller is not the owner");
      expect(
        await this.stableJoeStaking.isRewardToken(token1.address)
      ).to.be.equal(false);
      expect(await this.stableJoeStaking.rewardTokensLength()).to.be.equal(1);

      await this.stableJoeStaking
        .connect(this.dev)
        .addRewardToken(token1.address);
      await expect(
        this.stableJoeStaking.connect(this.dev).addRewardToken(token1.address)
      ).to.be.revertedWith("StableJoeStaking: token can't be added");
      expect(
        await this.stableJoeStaking.isRewardToken(token1.address)
      ).to.be.equal(true);
      expect(await this.stableJoeStaking.rewardTokensLength()).to.be.equal(2);

      await this.stableJoeStaking
        .connect(this.dev)
        .removeRewardToken(token1.address);
      expect(
        await this.stableJoeStaking.isRewardToken(token1.address)
      ).to.be.equal(false);
      expect(await this.stableJoeStaking.rewardTokensLength()).to.be.equal(1);
    });

    it("should allow setting a new deposit fee, only by owner", async function () {
      await this.stableJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("900")
      );
      expect(
        await this.joe.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(ethers.utils.parseEther("97"));
      expect(
        await this.joe.balanceOf(this.penaltyCollector.address)
      ).to.be.equal(ethers.utils.parseEther("3"));

      await expect(
        this.stableJoeStaking.connect(this.alice).setDepositFeePercent("0")
      ).to.be.revertedWith("Ownable: caller is not the owner");
      await expect(
        this.stableJoeStaking
          .connect(this.dev)
          .setDepositFeePercent(ethers.utils.parseEther("0.5"))
      ).to.be.revertedWith(
        "StableJoeStaking: deposit fee can't be greater than 50%"
      );

      await this.stableJoeStaking
        .connect(this.dev)
        .setDepositFeePercent(ethers.utils.parseEther("0.49"));
      expect(await this.stableJoeStaking.depositFeePercent()).to.be.equal(
        ethers.utils.parseEther("0.49")
      );

      await this.stableJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("800")
      );

      expect(
        await this.joe.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(
        ethers.utils.parseEther("97").add(ethers.utils.parseEther("51"))
      );
      expect(
        await this.joe.balanceOf(this.penaltyCollector.address)
      ).to.be.equal(
        ethers.utils.parseEther("3").add(ethers.utils.parseEther("49"))
      );
    });

    it("should allow emergency withdraw", async function () {
      await this.stableJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("300"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("700")
      );
      expect(
        await this.joe.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(ethers.utils.parseEther("291"));

      await this.rewardToken.mint(
        this.stableJoeStaking.address,
        ethers.utils.parseEther("100")
      ); // We send 100 Tokens to sJoe's address

      await this.stableJoeStaking.connect(this.alice).emergencyWithdraw(); // Alice shouldn't receive any token of the last reward
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("991")
      );
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        0
      );
      expect(
        await this.joe.balanceOf(this.stableJoeStaking.address)
      ).to.be.equal(0);
      const userInfo = await this.stableJoeStaking.getUserInfo(
        this.stableJoeStaking.address,
        this.rewardToken.address
      );
      expect(userInfo[0]).to.be.equal(0);
      expect(userInfo[1]).to.be.equal(0);
    });
  });

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    });
  });
});

const increase = (seconds) => {
  ethers.provider.send("evm_increaseTime", [seconds]);
  ethers.provider.send("evm_mine", []);
};
