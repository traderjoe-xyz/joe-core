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

    this.veJoePerSharePerSec = ethers.utils.parseEther("1");
    this.speedUpVeJoePerSharePerSec = ethers.utils.parseEther("1");
    this.speedUpThreshold = 5;
    this.speedUpDuration = 50;
    this.maxCapPct = 20000;

    this.veJoeStaking = await upgrades.deployProxy(this.VeJoeStakingCF, [
      this.joe.address, // _joe
      this.veJoe.address, // _veJoe
      this.veJoePerSharePerSec, // _veJoePerSharePerSec
      this.speedUpVeJoePerSharePerSec, // _speedUpVeJoePerSharePerSec
      this.speedUpThreshold, // _speedUpThreshold
      this.speedUpDuration, // _speedUpDuration
      this.maxCapPct, // _maxCapPct
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

  describe("setMaxCapPct", function () {
    it("should not allow non-owner to setMaxCapPct", async function () {
      await expect(
        this.veJoeStaking.connect(this.alice).setMaxCapPct(this.maxCapPct + 1)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should not allow owner to set lower maxCapPct", async function () {
      expect(await this.veJoeStaking.maxCapPct()).to.be.equal(this.maxCapPct);

      await expect(
        this.veJoeStaking.connect(this.dev).setMaxCapPct(this.maxCapPct - 1)
      ).to.be.revertedWith(
        "VeJoeStaking: expected new _maxCapPct to be greater than existing maxCapPct"
      );
    });

    it("should not allow owner to set maxCapPct greater than upper limit", async function () {
      await expect(
        this.veJoeStaking.connect(this.dev).setMaxCapPct(10000001)
      ).to.be.revertedWith(
        "VeJoeStaking: expected new _maxCapPct to be non-zero and <= 10000000"
      );
    });

    it("should allow owner to setMaxCapPct", async function () {
      expect(await this.veJoeStaking.maxCapPct()).to.be.equal(this.maxCapPct);

      await this.veJoeStaking
        .connect(this.dev)
        .setMaxCapPct(this.maxCapPct + 100);

      expect(await this.veJoeStaking.maxCapPct()).to.be.equal(
        this.maxCapPct + 100
      );
    });
  });

  describe("setVeJoePerSharePerSec", function () {
    it("should not allow non-owner to setVeJoePerSharePerSec", async function () {
      await expect(
        this.veJoeStaking
          .connect(this.alice)
          .setVeJoePerSharePerSec(ethers.utils.parseEther("1.5"))
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should not allow owner to set veJoePerSharePerSec greater than upper limit", async function () {
      await expect(
        this.veJoeStaking
          .connect(this.dev)
          .setVeJoePerSharePerSec(ethers.utils.parseUnits("1", 37))
      ).to.be.revertedWith(
        "VeJoeStaking: expected _veJoePerSharePerSec to be <= 1e36"
      );
    });

    it("should allow owner to setVeJoePerSharePerSec", async function () {
      expect(await this.veJoeStaking.veJoePerSharePerSec()).to.be.equal(
        this.veJoePerSharePerSec
      );

      await this.veJoeStaking
        .connect(this.dev)
        .setVeJoePerSharePerSec(ethers.utils.parseEther("1.5"));

      expect(await this.veJoeStaking.veJoePerSharePerSec()).to.be.equal(
        ethers.utils.parseEther("1.5")
      );
    });
  });

  describe("setSpeedUpThreshold", function () {
    it("should not allow non-owner to setSpeedUpThreshold", async function () {
      await expect(
        this.veJoeStaking.connect(this.alice).setSpeedUpThreshold(10)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should not allow owner to setSpeedUpThreshold to 0", async function () {
      await expect(
        this.veJoeStaking.connect(this.dev).setSpeedUpThreshold(0)
      ).to.be.revertedWith(
        "VeJoeStaking: expected _speedUpThreshold to be > 0 and <= 100"
      );
    });

    it("should not allow owner to setSpeedUpThreshold greater than 100", async function () {
      await expect(
        this.veJoeStaking.connect(this.dev).setSpeedUpThreshold(101)
      ).to.be.revertedWith(
        "VeJoeStaking: expected _speedUpThreshold to be > 0 and <= 100"
      );
    });

    it("should allow owner to setSpeedUpThreshold", async function () {
      expect(await this.veJoeStaking.speedUpThreshold()).to.be.equal(
        this.speedUpThreshold
      );

      await this.veJoeStaking.connect(this.dev).setSpeedUpThreshold(10);

      expect(await this.veJoeStaking.speedUpThreshold()).to.be.equal(10);
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
      // lastClaimTimestamp
      expect(beforeAliceUserInfo[2]).to.be.equal(0);
      // speedUpEndTimestamp
      expect(beforeAliceUserInfo[3]).to.be.equal(0);

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
      // lastClaimTimestamp
      expect(afterAliceUserInfo[2]).to.be.equal(depositBlock.timestamp);
      // speedUpEndTimestamp
      expect(afterAliceUserInfo[3]).to.be.equal(
        depositBlock.timestamp + this.speedUpDuration
      );
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
      // Should have sum of:
      // baseVeJoe =  100 * 30 = 3000 veJOE
      // speedUpVeJoe = 100 * 30 = 3000 veJOE
      expect(await this.veJoe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("6000")
      );
    });

    it("should receive speed up benefits after depositing speedUpThreshold with non-zero balance", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));

      await increase(this.speedUpDuration);

      await this.veJoeStaking.connect(this.alice).claim();

      const afterClaimAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      // speedUpTimestamp
      expect(afterClaimAliceUserInfo[3]).to.be.equal(0);

      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("5"));

      const secondDepositBlock = await ethers.provider.getBlock();

      const seconDepositAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      // speedUpTimestamp
      expect(seconDepositAliceUserInfo[3]).to.be.equal(
        secondDepositBlock.timestamp + this.speedUpDuration
      );
    });

    it("should not receive speed up benefits after depositing less than speedUpThreshold with non-zero balance", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));

      await increase(this.speedUpDuration);

      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("1"));

      const afterAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      // speedUpTimestamp
      expect(afterAliceUserInfo[3]).to.be.equal(0);
    });

    it("should receive speed up benefits after deposit with zero balance", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));

      await increase(100);

      await this.veJoeStaking
        .connect(this.alice)
        .withdraw(ethers.utils.parseEther("100"));

      await increase(100);

      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("1"));

      const secondDepositBlock = await ethers.provider.getBlock();

      const secondDepositAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      // speedUpEndTimestamp
      expect(secondDepositAliceUserInfo[3]).to.be.equal(
        secondDepositBlock.timestamp + this.speedUpDuration
      );
    });

    it("should have speed up period extended after depositing speedUpThreshold and currently receiving speed up benefits", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));

      const initialDepositBlock = await ethers.provider.getBlock();

      const initialDepositAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      const initialDepositSpeedUpEndTimestamp = initialDepositAliceUserInfo[3];

      expect(initialDepositSpeedUpEndTimestamp).to.be.equal(
        initialDepositBlock.timestamp + this.speedUpDuration
      );

      // Increase by some amount of time less than speedUpDuration
      await increase(this.speedUpDuration / 2);

      // Deposit speedUpThreshold amount so that speed up period gets extended
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("5"));

      const secondDepositBlock = await ethers.provider.getBlock();

      const secondDepositAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      const secondDepositSpeedUpEndTimestamp = secondDepositAliceUserInfo[3];

      expect(
        secondDepositSpeedUpEndTimestamp.gt(initialDepositSpeedUpEndTimestamp)
      ).to.be.equal(true);
      expect(secondDepositSpeedUpEndTimestamp).to.be.equal(
        secondDepositBlock.timestamp + this.speedUpDuration
      );
    });

    it("should have lastClaimTimestamp updated after depositing if holding max veJOE cap", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));

      // Increase by `maxCapPct` seconds to ensure that user will have max veJOE
      // after claiming
      await increase(this.maxCapPct);

      await this.veJoeStaking.connect(this.alice).claim();

      const claimBlock = await ethers.provider.getBlock();

      const claimAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      // lastClaimTimestamp
      expect(claimAliceUserInfo[2]).to.be.equal(claimBlock.timestamp);

      await increase(this.maxCapPct);

      const pendingVeJoe = await this.veJoeStaking.getPendingVeJoe(
        this.alice.address
      );
      expect(pendingVeJoe).to.be.equal(0);

      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("5"));

      const secondDepositBlock = await ethers.provider.getBlock();

      const secondDepositAliceUserInfo = await this.veJoeStaking.userInfos(
        this.alice.address
      );
      // lastClaimTimestamp
      expect(secondDepositAliceUserInfo[2]).to.be.equal(
        secondDepositBlock.timestamp
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

      await increase(this.speedUpDuration / 2);

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
        // Divide by 2 since half of it is from the speed up
        (await this.veJoe.balanceOf(this.alice.address)).div(2)
      );
      // lastClaimTimestamp
      expect(beforeAliceUserInfo[2]).to.be.equal(claimBlock.timestamp);
      // speedUpEndTimestamp
      expect(beforeAliceUserInfo[3]).to.be.equal(
        depositBlock.timestamp + this.speedUpDuration
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
      // lastClaimTimestamp
      expect(afterAliceUserInfo[2]).to.be.equal(withdrawBlock.timestamp);
      // speedUpEndTimestamp
      expect(afterAliceUserInfo[3]).to.be.equal(0);

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
      // Should be sum of:
      // baseVeJoe = 100 * 50 = 5000
      // speedUpVeJoe = 100 * 50 = 5000
      expect(await this.veJoe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("10000")
      );
    });

    it("should receive correct veJOE if veJoePerSharePerSec is updated multiple times", async function () {
      await this.veJoeStaking
        .connect(this.alice)
        .deposit(ethers.utils.parseEther("100"));

      await increase(9);

      await this.veJoeStaking
        .connect(this.dev)
        .setVeJoePerSharePerSec(ethers.utils.parseEther("2"));

      await increase(9);

      await this.veJoeStaking
        .connect(this.dev)
        .setVeJoePerSharePerSec(ethers.utils.parseEther("1.5"));

      await increase(9);

      // Check veJoe balance before claim
      expect(await this.veJoe.balanceOf(this.alice.address)).to.be.equal(0);

      await this.veJoeStaking.connect(this.alice).claim();

      // Check veJoe balance after claim
      // For baseVeJoe, we're expected to have been generating at a rate of 1 for
      // the first 10 seconds, a rate of 2 for the next 10 seconds, and a rate of
      // 1.5 for the last 10 seconds, i.e.:
      // baseVeJoe = 100 * 10 * 1 + 100 * 10 * 2 + 100 * 10 * 1.5 = 4500
      // speedUpVeJoe = 100 * 30 = 3000
      expect(await this.veJoe.balanceOf(this.alice.address)).to.be.equal(
        ethers.utils.parseEther("7500")
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
      // Increase should be `secondsElapsed * veJoePerSharePerSec * ACC_VEJOE_PER_SHARE_PER_SEC_PRECISION`:
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
