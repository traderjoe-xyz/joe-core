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

  describe("setter methods", function () {
    it("should allow owner to setMaxCap", async function () {
      expect(await this.veJoeStaking.maxCap()).to.be.equal(100);

      await this.veJoeStaking.connect(this.dev).setMaxCap(200);

      expect(await this.veJoeStaking.maxCap()).to.be.equal(200);
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
