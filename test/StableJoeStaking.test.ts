import { ethers, network } from "hardhat"
import { expect } from "chai"
import { describe } from "mocha"
const hre = require("hardhat")

describe("Stable Joe Staking", function () {
  before(async function () {
    this.StableJoeStakingCF = await ethers.getContractFactory("StableJoeStaking")
    this.JoeTokenCF = await ethers.getContractFactory("JoeToken")

    this.signers = await ethers.getSigners()
    this.dev = this.signers[0]
    this.alice = this.signers[1]
    this.bob = this.signers[2]
    this.carol = this.signers[3]
  })

  beforeEach(async function () {
    this.rewardToken = await this.JoeTokenCF.deploy()
    this.moJoe = await this.JoeTokenCF.deploy()

    await this.moJoe.mint(this.alice.address, "1000000000000000000000")
    await this.moJoe.mint(this.bob.address, "1000000000000000000000")
    await this.moJoe.mint(this.carol.address, "1000000000000000000000")

    this.sJoe = await hre.upgrades.deployProxy(this.StableJoeStakingCF, [this.rewardToken.address, this.moJoe.address])
  })

  describe("should allow deposits and withdraws", function () {
    it("should allow deposits and withdraws of multiple users", async function () {
      await this.moJoe.connect(this.alice).approve(this.sJoe.address, "100000000000000000000000000000000")
      await this.moJoe.connect(this.bob).approve(this.sJoe.address, "100000000000000000000000000000000")
      await this.moJoe.connect(this.carol).approve(this.sJoe.address, "100000000000000000000000000000000")

      await this.sJoe.connect(this.alice).deposit("100000000000000000000")
      expect(await this.moJoe.balanceOf(this.alice.address)).to.be.equal("900000000000000000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("100000000000000000000")

      await this.sJoe.connect(this.bob).deposit("200000000000000000000")
      expect(await this.moJoe.balanceOf(this.bob.address)).to.be.equal("800000000000000000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("300000000000000000000")

      await this.sJoe.connect(this.carol).deposit("300000000000000000000")
      expect(await this.moJoe.balanceOf(this.carol.address)).to.be.equal("700000000000000000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("600000000000000000000")

      await this.sJoe.connect(this.alice).withdraw("100000000000000000000")
      expect(await this.moJoe.balanceOf(this.alice.address)).to.be.equal("1000000000000000000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("500000000000000000000")

      await this.sJoe.connect(this.carol).withdraw("100000000000000000000")
      expect(await this.moJoe.balanceOf(this.carol.address)).to.be.equal("800000000000000000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("400000000000000000000")

      await this.sJoe.connect(this.bob).withdraw("1")
      expect(await this.moJoe.balanceOf(this.bob.address)).to.be.equal("800000000000000000001")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("399999999999999999999")
    })

    it("should allow deposits and withdraws of multiple users and distribute rewards accordingly", async function () {
      await this.moJoe.connect(this.alice).approve(this.sJoe.address, "100000000000000000000000000000000")
      await this.moJoe.connect(this.bob).approve(this.sJoe.address, "100000000000000000000000000000000")
      await this.moJoe.connect(this.carol).approve(this.sJoe.address, "100000000000000000000000000000000")

      await this.sJoe.connect(this.alice).deposit("100000000000000000000")
      expect(await this.moJoe.balanceOf(this.alice.address)).to.be.equal("900000000000000000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("100000000000000000000")

      await this.sJoe.connect(this.bob).deposit("200000000000000000000")
      expect(await this.moJoe.balanceOf(this.bob.address)).to.be.equal("800000000000000000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("300000000000000000000")

      await this.sJoe.connect(this.carol).deposit("300000000000000000000")
      expect(await this.moJoe.balanceOf(this.carol.address)).to.be.equal("700000000000000000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("600000000000000000000")

      await this.rewardToken.mint(this.sJoe.address, "100000000000000000000") // we send 100 Tokens to sJoe's address

      await this.sJoe.connect(this.alice).withdraw("100000000000000000000")
      expect(await this.moJoe.balanceOf(this.alice.address)).to.be.equal("1000000000000000000000")
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal("16666666666600000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("500000000000000000000")

      await this.sJoe.connect(this.carol).withdraw("100000000000000000000")
      expect(await this.moJoe.balanceOf(this.carol.address)).to.be.equal("800000000000000000000")
      expect(await this.rewardToken.balanceOf(this.carol.address)).to.be.equal("49999999999800000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("400000000000000000000")

      await this.sJoe.connect(this.bob).withdraw("0")
      expect(await this.moJoe.balanceOf(this.bob.address)).to.be.equal("800000000000000000000")
      expect(await this.rewardToken.balanceOf(this.bob.address)).to.be.equal("33333333333200000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("400000000000000000000")
    })

    it("should allow deposits and withdraws of multiple users and distribute rewards accordingly even if someone enters or leaves", async function () {
      await this.moJoe.connect(this.alice).approve(this.sJoe.address, "100000000000000000000000000000000")
      await this.moJoe.connect(this.bob).approve(this.sJoe.address, "100000000000000000000000000000000")
      await this.moJoe.connect(this.carol).approve(this.sJoe.address, "100000000000000000000000000000000")

      await this.sJoe.connect(this.alice).deposit("300000000000000000000")
      await this.sJoe.connect(this.carol).deposit("300000000000000000000")
      expect(await this.moJoe.balanceOf(this.alice.address)).to.be.equal("700000000000000000000")
      expect(await this.moJoe.balanceOf(this.carol.address)).to.be.equal("700000000000000000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("600000000000000000000")

      await this.rewardToken.mint(this.sJoe.address, "100000000000000000000") // we send 100 Tokens to sJoe's address

      await this.sJoe.connect(this.bob).deposit("300000000000000000000") // bob enters after the distribution, he shouldn't receive any reward
      await this.sJoe.connect(this.bob).withdraw("0")
      expect(await this.moJoe.balanceOf(this.bob.address)).to.be.equal("700000000000000000000")
      expect(await this.rewardToken.balanceOf(this.bob.address)).to.be.equal("0")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("900000000000000000000")

      await this.sJoe.connect(this.alice).deposit("300000000000000000000") // alice enters again to try to get more rewards
      await this.sJoe.connect(this.alice).withdraw("600000000000000000000")
      expect(await this.moJoe.balanceOf(this.alice.address)).to.be.equal("1000000000000000000000")
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal("49999999999800000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("600000000000000000000")

      await this.rewardToken.mint(this.sJoe.address, "200000000000000000000") // we send 200 Tokens to sJoe's address

      await this.sJoe.connect(this.bob).withdraw("0") // bob should only receive half of the last reward
      expect(await this.moJoe.balanceOf(this.bob.address)).to.be.equal("700000000000000000000")
      expect(await this.rewardToken.balanceOf(this.bob.address)).to.be.equal("99999999999900000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("600000000000000000000")

      await this.sJoe.connect(this.carol).withdraw("300000000000000000000") // carol should receive both
      expect(await this.moJoe.balanceOf(this.carol.address)).to.be.equal("1000000000000000000000")
      expect(await this.rewardToken.balanceOf(this.carol.address)).to.be.equal("149999999999700000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("300000000000000000000")

      await this.sJoe.connect(this.alice).withdraw("0") // alice shouldn't receive any token of the last reward
      expect(await this.moJoe.balanceOf(this.alice.address)).to.be.equal("1000000000000000000000")
      expect((await this.rewardToken.balanceOf(this.alice.address)) - 49999999999800000000).to.be.equal(0)
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("300000000000000000000")
    })

    it("pending tokens function should return the same number of token that user actually receive", async function () {
      await this.moJoe.connect(this.alice).approve(this.sJoe.address, "100000000000000000000000000000000")

      await this.sJoe.connect(this.alice).deposit("300000000000000000000")
      expect(await this.moJoe.balanceOf(this.alice.address)).to.be.equal("700000000000000000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("300000000000000000000")

      await this.rewardToken.mint(this.sJoe.address, "100000000000000000000") // we send 100 Tokens to sJoe's address

      const pendingReward = await this.sJoe.pendingToken(this.alice.address)
      await this.sJoe.connect(this.alice).withdraw("0") // alice shouldn't receive any token of the last reward
      expect(await this.moJoe.balanceOf(this.alice.address)).to.be.equal("700000000000000000000")
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(pendingReward)
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("300000000000000000000")
    })

    it("should allow emergency withdraw", async function () {
      await this.moJoe.connect(this.alice).approve(this.sJoe.address, "100000000000000000000000000000000")

      await this.sJoe.connect(this.alice).deposit("300000000000000000000")
      expect(await this.moJoe.balanceOf(this.alice.address)).to.be.equal("700000000000000000000")
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal("300000000000000000000")

      await this.rewardToken.mint(this.sJoe.address, "100000000000000000000") // we send 100 Tokens to sJoe's address

      await this.sJoe.connect(this.alice).emergencyWithdraw() // alice shouldn't receive any token of the last reward
      expect(await this.moJoe.balanceOf(this.alice.address)).to.be.equal("1000000000000000000000")
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(0)
      expect(await this.moJoe.balanceOf(this.sJoe.address)).to.be.equal(0)
      const userInfo = await this.sJoe.userInfo(this.sJoe.address)
      expect(userInfo.amount).to.be.equal(0)
      expect(userInfo.rewardDebt).to.be.equal(0)
    })
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
