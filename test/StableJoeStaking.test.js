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

    this.sJoe = await hre.upgrades.deployProxy(this.StableJoeStakingCF, [
      this.rewardToken.address,
      this.joe.address,
      ethers.utils.parseEther("0.03"),
    ]);

    await this.joe
      .connect(this.alice)
      .approve(this.sJoe.address, ethers.utils.parseEther("100000"));
    await this.joe
      .connect(this.bob)
      .approve(this.sJoe.address, ethers.utils.parseEther("100000"));
    await this.joe
      .connect(this.carol)
      .approve(this.sJoe.address, ethers.utils.parseEther("100000"));
  });

  describe("should allow deposits and withdraws", function () {
    it("should allow deposits and withdraws of multiple users", async function () {
      await this.sJoe
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("900")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("100")
      );
      expect(
        (await this.sJoe.getUserInfo(this.alice.address, this.joe.address))[0]
      ).to.be.equal(ethers.utils.parseEther("97"));

      await this.sJoe.connect(this.bob).deposit(ethers.utils.parseEther("200"));
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(
        ethers.utils.parseEther("800")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("300")
      );
      expect(
        (await this.sJoe.getUserInfo(this.bob.address, this.joe.address))[0]
      ).to.be.equal(ethers.utils.parseEther("194"));

      await this.sJoe
        .connect(this.carol)
        .deposit(ethers.utils.parseEther("300"));
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(
        ethers.utils.parseEther("700")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("600")
      );
      expect(
        (await this.sJoe.getUserInfo(this.carol.address, this.joe.address))[0]
      ).to.be.equal(ethers.utils.parseEther("291"));

      await this.sJoe
        .connect(this.alice)
        .withdraw(ethers.utils.parseEther("97"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("997")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("503")
      );
      expect(
        (await this.sJoe.getUserInfo(this.alice.address, this.joe.address))[0]
      ).to.be.equal(0);

      await this.sJoe
        .connect(this.carol)
        .withdraw(ethers.utils.parseEther("100"));
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(
        ethers.utils.parseEther("800")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("403")
      );
      expect(
        (await this.sJoe.getUserInfo(this.carol.address, this.joe.address))[0]
      ).to.be.equal(ethers.utils.parseEther("191"));

      await this.sJoe.connect(this.bob).withdraw("1");
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(
        ethers.utils.parseEther("800.000000000000000001")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("402.999999999999999999")
      );
      expect(
        (await this.sJoe.getUserInfo(this.bob.address, this.joe.address))[0]
      ).to.be.equal(ethers.utils.parseEther("193.999999999999999999"));
    });

    it("should update variables accordingly", async function () {
      await this.sJoe.connect(this.alice).deposit("1");

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.sJoe.address, ethers.utils.parseEther("1"));
      expect(await this.rewardToken.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("1")
      );
      expect(
        await this.sJoe.lastRewardBalance(this.rewardToken.address)
      ).to.be.equal("0");

      await increase(86400);

      expect(await this.rewardToken.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("1")
      );
      expect(
        await this.sJoe.pendingTokens(
          this.alice.address,
          this.rewardToken.address
        )
      ).to.be.equal(ethers.utils.parseEther("1"));

      // Making sure that `pendingTokens` still return the accurate tokens even after updating pools
      await this.sJoe.updatePool(this.rewardToken.address);
      expect(
        await this.sJoe.pendingTokens(
          this.alice.address,
          this.rewardToken.address
        )
      ).to.be.equal(ethers.utils.parseEther("1"));

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.sJoe.address, ethers.utils.parseEther("1"));
      await increase(86_400);

      // Should be equal to 2, the previous reward and the new one
      expect(
        await this.sJoe.pendingTokens(
          this.alice.address,
          this.rewardToken.address
        )
      ).to.be.equal(ethers.utils.parseEther("2"));

      // Making sure that `pendingTokens` still return the accurate tokens even after updating pools
      await this.sJoe.updatePool(this.rewardToken.address);
      expect(
        await this.sJoe.pendingTokens(
          this.alice.address,
          this.rewardToken.address
        )
      ).to.be.equal(ethers.utils.parseEther("2"));
    });

    it("should allow deposits and withdraws of multiple users and distribute rewards accordingly", async function () {
      await this.sJoe
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("900")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("100")
      );
      expect(
        (await this.sJoe.getUserInfo(this.alice.address, this.joe.address))[0]
      ).to.be.equal(ethers.utils.parseEther("97"));

      await this.sJoe.connect(this.bob).deposit(ethers.utils.parseEther("200"));
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(
        ethers.utils.parseEther("800")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("300")
      );
      expect(
        (await this.sJoe.getUserInfo(this.bob.address, this.joe.address))[0]
      ).to.be.equal(ethers.utils.parseEther("194"));

      await this.sJoe
        .connect(this.carol)
        .deposit(ethers.utils.parseEther("300"));
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(
        ethers.utils.parseEther("700")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("600")
      );
      expect(
        (await this.sJoe.getUserInfo(this.carol.address, this.joe.address))[0]
      ).to.be.equal(ethers.utils.parseEther("291"));

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.sJoe.address, ethers.utils.parseEther("6"));
      await this.sJoe.updatePool(this.rewardToken.address);
      await increase(86_400);

      await this.sJoe
        .connect(this.alice)
        .withdraw(ethers.utils.parseEther("97"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("997")
      );
      expect(
        await this.rewardToken.balanceOf(this.alice.address)
      ).to.be.closeTo(
        ethers.utils.parseEther("1"),
        ethers.utils.parseEther("0.0001")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("503")
      );
      expect(
        (await this.sJoe.getUserInfo(this.alice.address, this.joe.address))[0]
      ).to.be.equal(0);

      await this.sJoe
        .connect(this.carol)
        .withdraw(ethers.utils.parseEther("100"));
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(
        ethers.utils.parseEther("800")
      );
      expect(
        await this.rewardToken.balanceOf(this.carol.address)
      ).to.be.closeTo(
        ethers.utils.parseEther("3"),
        ethers.utils.parseEther("0.0001")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("403")
      );
      expect(
        (await this.sJoe.getUserInfo(this.carol.address, this.joe.address))[0]
      ).to.be.equal(ethers.utils.parseEther("191"));

      await this.sJoe.connect(this.bob).withdraw("0");
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(
        ethers.utils.parseEther("800")
      );
      expect(await this.rewardToken.balanceOf(this.bob.address)).to.be.closeTo(
        ethers.utils.parseEther("2"),
        ethers.utils.parseEther("0.0001")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("403")
      );
      expect(
        (await this.sJoe.getUserInfo(this.bob.address, this.joe.address))[0]
      ).to.be.equal(ethers.utils.parseEther("194"));
    });

    it("should distribute token accordingly even if update isn't called every day", async function () {
      await this.sJoe.connect(this.alice).deposit(1);
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        0
      );

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.sJoe.address, ethers.utils.parseEther("1"));
      await increase(86_400);
      await this.sJoe.connect(this.alice).withdraw(0);
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("1")
      );

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.sJoe.address, ethers.utils.parseEther("1"));
      await increase(10 * 86_400);
      await this.sJoe.connect(this.alice).withdraw(0);
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("2")
      );
    });

    it("should allow deposits and withdraws of multiple users and distribute rewards accordingly even if someone enters or leaves", async function () {
      await this.sJoe
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));
      await this.sJoe
        .connect(this.carol)
        .deposit(ethers.utils.parseEther("100"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("900")
      );
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(
        ethers.utils.parseEther("900")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("200")
      );

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.sJoe.address, ethers.utils.parseEther("4"));
      await this.sJoe.updatePool(this.rewardToken.address);
      await increase(86_400);

      await this.sJoe.connect(this.bob).deposit(ethers.utils.parseEther("200")); // Bob enters
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(
        ethers.utils.parseEther("800")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("400")
      );

      await this.sJoe
        .connect(this.carol)
        .withdraw(ethers.utils.parseEther("97"));
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(
        ethers.utils.parseEther("997")
      );
      expect(
        await this.rewardToken.balanceOf(this.carol.address)
      ).to.be.closeTo(
        ethers.utils.parseEther("2"),
        ethers.utils.parseEther("0.0001")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("303")
      );

      await this.sJoe
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100")); // Alice enters again to try to get more rewards
      await this.sJoe
        .connect(this.alice)
        .withdraw(ethers.utils.parseEther("194"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("994")
      );
      // She gets the same reward as Carol, and a bit more as some time elapsed
      const aliceBalance = await this.rewardToken.balanceOf(this.alice.address);
      expect(aliceBalance).to.be.closeTo(
        ethers.utils.parseEther("2"),
        ethers.utils.parseEther("0.0001")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("209")
      );

      await this.rewardToken
        .connect(this.joeMaker)
        .transfer(this.sJoe.address, ethers.utils.parseEther("4"));
      await increase(86_400);

      await this.sJoe.connect(this.bob).withdraw("0");
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(
        ethers.utils.parseEther("800")
      );
      expect(await this.rewardToken.balanceOf(this.bob.address)).to.be.closeTo(
        ethers.utils.parseEther("4"),
        ethers.utils.parseEther("0.0001")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("209")
      );

      await this.sJoe.connect(this.alice).withdraw("0"); // Alice shouldn't receive any token of the last reward
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("994")
      );
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        aliceBalance
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("209")
      );
    });

    it("pending tokens function should return the same number of token that user actually receive", async function () {
      await this.sJoe
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("300"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("700")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("300")
      );

      await this.rewardToken.mint(
        this.sJoe.address,
        ethers.utils.parseEther("100")
      ); // We send 100 Tokens to sJoe's address

      const pendingReward = await this.sJoe.pendingTokens(
        this.alice.address,
        this.rewardToken.address
      );
      await this.sJoe.connect(this.alice).withdraw("0"); // Alice shouldn't receive any token of the last reward
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("700")
      );
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        pendingReward
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("300")
      );
    });

    it("should allow emergency withdraw", async function () {
      await this.sJoe
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("300"));
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("700")
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(
        ethers.utils.parseEther("300")
      );

      await this.rewardToken.mint(
        this.sJoe.address,
        ethers.utils.parseEther("100")
      ); // We send 100 Tokens to sJoe's address

      await this.sJoe.connect(this.alice).emergencyWithdraw(); // Alice shouldn't receive any token of the last reward
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("991")
      );
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        0
      );
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("9"));
      const userInfo = await this.sJoe.getUserInfo(this.sJoe.address, this.rewardToken.address);
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
