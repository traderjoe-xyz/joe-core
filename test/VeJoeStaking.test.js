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

    this.veJoeStaking = await upgrades.deployProxy(this.VeJoeStakingCF, [
      this.joe.address, // _joe
      this.veJoe.address, // _veJoe
      ethers.utils.parseEther("5"), // _baseGenerationRate
      ethers.utils.parseEther("10"), // _boostedGenerationRate
      5, // _boostedThreshold
      300, // _boostedDuration
      100, // _maxCap
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
      expect(await this.veJoeStaking.maxCap()).to.be.equal(100);

      await expect(
        this.veJoeStaking.connect(this.dev).setMaxCap(99)
      ).to.be.revertedWith(
        "VeJoeStaking: expected new _maxCap to be greater than existing maxCap"
      );
    });

    it("should not allow owner to set maxCap greater than upper limit", async function () {
      expect(await this.veJoeStaking.maxCap()).to.be.equal(100);

      await expect(
        this.veJoeStaking.connect(this.dev).setMaxCap(100001)
      ).to.be.revertedWith(
        "VeJoeStaking: expected new _maxCap to be greater than 0 and leq to 100000"
      );
    });

    it("should allow owner to setMaxCap", async function () {
      expect(await this.veJoeStaking.maxCap()).to.be.equal(100);

      await this.veJoeStaking.connect(this.dev).setMaxCap(200);

      expect(await this.veJoeStaking.maxCap()).to.be.equal(200);
    });
  });

  describe("setBaseGenerationRate", function () {
    it("should not allow non-owner to setMaxCap", async function () {
      await expect(
        this.veJoeStaking
          .connect(this.alice)
          .setBaseGenerationRate(ethers.utils.parseEther("6"))
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should not allow owner to setBaseGenerationRate greater than boostedGenerationRate", async function () {
      expect(await this.veJoeStaking.boostedGenerationRate()).to.be.equal(
        ethers.utils.parseEther("10")
      );

      await expect(
        this.veJoeStaking
          .connect(this.dev)
          .setBaseGenerationRate(ethers.utils.parseEther("11"))
      ).to.be.revertedWith(
        "VeJoeStaking: expected new _baseGenerationRate to be less than boostedGenerationRate"
      );
    });

    it("should allow owner to setBaseGenerationRate", async function () {
      expect(await this.veJoeStaking.baseGenerationRate()).to.be.equal(
        ethers.utils.parseEther("5")
      );

      await this.veJoeStaking
        .connect(this.dev)
        .setBaseGenerationRate(ethers.utils.parseEther("6"));

      expect(await this.veJoeStaking.baseGenerationRate()).to.be.equal(
        ethers.utils.parseEther("6")
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
