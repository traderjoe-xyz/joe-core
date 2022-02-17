// @ts-nocheck
const { ethers, network, upgrades } = require("hardhat");
const { expect } = require("chai");
const { describe } = require("mocha");

describe("VeJoe Staking", function () {
  before(async function () {
    this.VeJoeStakingCF = await ethers.getContractFactory("VeJoeStaking");
    this.VeJoeTokenCF = await ethers.getContractFactory("VeJoeToken");
    this.JoeTokenCF = await ethers.getContractFactory("JoeToken");

    this.signers = await ethers.getSigners();
    this.dev = this.signers[0];
    this.alice = this.signers[1];
    this.bob = this.signers[2];
    this.carol = this.signers[3];
  });

  beforeEach(async function () {
    this.veJoe = await this.VeJoeTokenCF.deploy();
    this.joe = await this.JoeTokenCF.deploy();

    await this.joe.mint(this.alice.address, ethers.utils.parseEther("1000"));
    await this.joe.mint(this.bob.address, ethers.utils.parseEther("1000"));
    await this.joe.mint(this.carol.address, ethers.utils.parseEther("1000"));

    this.baseGenerationRate = ethers.utils.parseEther("1");
    this.maxCap = 200;

    this.veJoeStaking = await upgrades.deployProxy(this.VeJoeStakingCF, [
      this.joe.address, // _joe
      this.veJoe.address, // _veJoe
      this.baseGenerationRate, // _baseGenerationRate
      this.maxCap, // _maxCap
    ]);
    await this.veJoe.transferOwnership(this.veJoeStaking.address);

    await this.joe
      .connect(this.alice)
      .approve(this.veJoeStaking.address, ethers.utils.parseEther("100000"));
    await this.joe
      .connect(this.bob)
      .approve(this.veJoeStaking.address, ethers.utils.parseEther("100000"));
    await this.joe
      .connect(this.carol)
      .approve(this.veJoeStaking.address, ethers.utils.parseEther("100000"));
  });

  describe("setMaxCap", function () {
    it("should not allow non-owner to setMaxCap", async function () {
      await expect(
        this.veJoeStaking.connect(this.alice).setMaxCap(200)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should not allow owner to set lower maxCap", async function () {
      expect(await this.veJoeStaking.maxCap()).to.be.equal(this.maxCap);

      await expect(
        this.veJoeStaking.connect(this.dev).setMaxCap(99)
      ).to.be.revertedWith(
        "VeJoeStaking: expected new _maxCap to be greater than existing maxCap"
      );
    });

    it("should not allow owner to set maxCap greater than upper limit", async function () {
      await expect(
        this.veJoeStaking.connect(this.dev).setMaxCap(100001)
      ).to.be.revertedWith(
        "VeJoeStaking: expected new _maxCap to be non-zero and <= 100000"
      );
    });

    it("should allow owner to setMaxCap", async function () {
      expect(await this.veJoeStaking.maxCap()).to.be.equal(this.maxCap);

      await this.veJoeStaking.connect(this.dev).setMaxCap(this.maxCap + 100);

      expect(await this.veJoeStaking.maxCap()).to.be.equal(this.maxCap + 100);
    });
  });

  describe("setBaseGenerationRate", function () {
    it("should not allow non-owner to setMaxCap", async function () {
      await expect(
        this.veJoeStaking
          .connect(this.alice)
          .setBaseGenerationRate(ethers.utils.parseEther("1.5"))
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should allow owner to setBaseGenerationRate", async function () {
      expect(await this.veJoeStaking.baseGenerationRate()).to.be.equal(
        this.baseGenerationRate
      );

      await this.veJoeStaking
        .connect(this.dev)
        .setBaseGenerationRate(ethers.utils.parseEther("1.5"));

      expect(await this.veJoeStaking.baseGenerationRate()).to.be.equal(
        ethers.utils.parseEther("1.5")
      );
    });
  });

  describe("deposit", function () {
    it("should not allow deposit 0", async function () {
      await expect(
        this.veJoeStaking.connect(this.alice).deposit(0)
      ).to.be.revertedWith(
        "VeJoeStaking: expected deposit amount to be greater than zero"
      );
    });

    it("should have correct updated user info after first time deposit", async function () {
      const beforeAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      // balance
      expect(beforeAliceUserInfo[0]).to.be.equal(0);
      // rewardDebt
      expect(beforeAliceUserInfo[1]).to.be.equal(0);

      // Check joe balance before deposit
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("1000")
      );

      const depositAmount = ethers.utils.parseEther("100");
      await this.veJoeStaking.connect(this.alice).deposit(depositAmount);
      const depositBlock = await ethers.provider.getBlock();

      // Check joe balance after deposit
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("900")
      );

      const afterAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      // balance
      expect(afterAliceUserInfo[0]).to.be.equal(depositAmount);
      // debtReward
      expect(afterAliceUserInfo[1]).to.be.equal(0);
    });

    it("should have correct updated user balance after deposit with non-zero balance", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));

      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("5"));

      const afterAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      // balance
      expect(afterAliceUserInfo[0]).to.be.equal(ethers.utils.parseEther("105"));
    });

    it("should claim pending veJOE upon depositing with non-zero balance", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));

      await increase(29);

      // Check veJoe balance before deposit
      expect(await this.veJoe.balanceOf(this.alice.address)).to.be.equal(0);

      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("1"));

      // Check veJoe balance after deposit
      // Should have 100 * 30 = 3000 veJOE
      expect(await this.veJoe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("3000")
      );
    });
  });

  describe("withdraw", function () {
    it("should not allow withdraw 0", async function () {
      await expect(
        this.veJoeStaking.connect(this.alice).withdraw(0)
      ).to.be.revertedWith(
        "VeJoeStaking: expected withdraw amount to be greater than zero"
      );
    });

    it("should not allow withdraw amount greater than user balance", async function () {
      await expect(
        this.veJoeStaking.connect(this.alice).withdraw(1)
      ).to.be.revertedWith(
        "VeJoeStaking: cannot withdraw greater amount of JOE than currently staked"
      );
    });

    it("should have correct updated user info and balances after withdraw", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));
      const depositBlock = await ethers.provider.getBlock();

      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("900")
      );

      await increase(this.boostedDuration / 2);

      await this.veJoeStaking.connect(this.alice).claim();
      const claimBlock = await ethers.provider.getBlock();

      expect(await this.veJoe.balanceOf(this.alice.address)).to.not.be.equal(0);

      const beforeAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      // balance
      expect(beforeAliceUserInfo[0]).to.be.equal(
        ethers.utils.parseEther("100")
      );
      // rewardDebt
      expect(beforeAliceUserInfo[1]).to.be.equal(
        await this.veJoe.balanceOf(this.alice.address)
      );

      await this.veJoeStaking
        .connect(this.alice)
        .withdraw(ethers.utils.parseEther("5"));
      const withdrawBlock = await ethers.provider.getBlock();

      // Check user info fields are updated correctly
      const afterAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      // balance
      expect(afterAliceUserInfo[0]).to.be.equal(ethers.utils.parseEther("95"));
      // rewardDebt
      expect(afterAliceUserInfo[1]).to.be.equal(
        (await this.veJoeStaking.accVeJoePerShare()).mul(95)
      );

      // Check user token balances are updated correctly
      expect(await this.veJoe.balanceOf(this.alice.address)).to.be.equal(0);
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("905")
      );
    });
  });

  describe("claim", function () {
    it("should not be able to claim with zero balance", async function () {
      await expect(
        this.veJoeStaking.connect(this.alice).claim()
      ).to.be.revertedWith(
        "VeJoeStaking: cannot claim veJOE when no JOE is staked"
      );
    });

    it("should update lastRewardTimestamp on claim", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));

      await increase(100);

      await this.veJoeStaking.connect(this.alice).claim();
      const claimBlock = await ethers.provider.getBlock();

      // lastRewardTimestamp
      expect(await this.veJoeStaking.lastRewardTimestamp()).to.be.equal(
        claimBlock.timestamp
      );
    });

    it("should receive veJOE on claim", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));

      await increase(49);

      // Check veJoe balance before claim
      expect(await this.veJoe.balanceOf(this.alice.address)).to.be.equal(0);

      await this.veJoeStaking.connect(this.alice).claim();

      // Check veJoe balance after claim
      expect(await this.veJoe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("5000")
      );
    });

    it("should receive correct veJOE if baseGenerationRate is updated multiple times", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));

      await increase(9);

      await this.veJoeStaking
        .connect(this.dev)
        .setBaseGenerationRate(ethers.utils.parseEther("2"));

      await increase(9);

      await this.veJoeStaking
        .connect(this.dev)
        .setBaseGenerationRate(ethers.utils.parseEther("1.5"));

      await increase(9);

      // Check veJoe balance before claim
      expect(await this.veJoe.balanceOf(this.alice.address)).to.be.equal(0);

      await this.veJoeStaking.connect(this.alice).claim();

      // Check veJoe balance after claim
      // Expected to have been generating at a rate of 1 for the first 10 seconds,
      // a rate of 2 for the next 10 seconds, and a rate of 1.5 for the last 10
      // seconds, i.e.:
      // 100 * 10 * 1 + 100 * 10 * 2 + 100 * 10 * 1.5 = 4500
      expect(await this.veJoe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("4500")
      );
    });
  });

  describe("updateRewardVars", function () {
    it("should have correct reward vars after time passes", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));

      const block = await ethers.provider.getBlock();
      await increase(29);

      const accVeJoePerShareBeforeUpdate =
        await this.veJoeStaking.accVeJoePerShare();
      await this.veJoeStaking.connect(this.dev).updateRewardVars();

      expect(await this.veJoeStaking.lastRewardTimestamp()).to.be.equal(
        block.timestamp + 30
      );
      // Increase should be `secondsElapsed * baseGenerationRate * ACC_VEJOE_PER_SHARE_PRECISION`:
      // = 30 * 1 * 1e18
      expect(await this.veJoeStaking.accVeJoePerShare()).to.be.equal(
        accVeJoePerShareBeforeUpdate.add(ethers.utils.parseEther("30"))
      );
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
