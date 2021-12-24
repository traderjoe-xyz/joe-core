import { ethers, network } from "hardhat"
import { expect } from "chai"
import { duration, increase } from "./utilities"
import { describe } from "mocha"
const hre = require("hardhat")

describe("JoeBar", function () {
  before(async function () {
    this.JoeToken = await ethers.getContractFactory("JoeToken")
    this.JoeBarV2 = await ethers.getContractFactory("JoeBarV2")
    this.BarRewarder = await ethers.getContractFactory("BarRewarderPerSec")

    this.signers = await ethers.getSigners()
    this.dev = this.signers[0]
    this.alice = this.signers[1]
    this.bob = this.signers[2]
    this.carol = this.signers[3]
  })

  beforeEach(async function () {
    this.joe = await this.JoeToken.deploy()
    this.bar = await hre.upgrades.deployProxy(this.JoeBarV2, [this.joe.address, "500"])

    this.rewarder = await this.BarRewarder.deploy(this.joe.address, this.bar.address, "1500")

    await this.bar.setRewarder(this.rewarder.address)
    await this.joe.mint(this.alice.address, "100000000000000000000")
    await this.joe.mint(this.bob.address, "100000000000000000000")
    await this.joe.mint(this.carol.address, "100000000000000000000")
  })

  it("should allow to set entryFee from owner only", async function () {
    await this.bar.connect(this.dev).setEntryFee("5000")

    await expect(this.bar.connect(this.dev).setEntryFee("5001")).to.be.revertedWith("JoeBarV2: entryFee too high")

    await expect(this.bar.connect(this.alice).setEntryFee("0")).to.be.revertedWith("Ownable: caller is not the owner")
    expect(await this.bar.entryFee()).to.be.equal("5000")
  })

  it("should not allow enter if not enough approve", async function () {
    await expect(this.bar.connect(this.alice).enter("100000000000000000000")).to.be.revertedWith("ERC20: transfer amount exceeds allowance")
    await this.joe.connect(this.alice).approve(this.bar.address, "50000000000000000000")
    await expect(this.bar.connect(this.alice).enter("100000000000000000000")).to.be.revertedWith("ERC20: transfer amount exceeds allowance")
    await this.joe.connect(this.alice).approve(this.bar.address, "100000000000000000000")
    await this.bar.connect(this.alice).enter("100000000000000000000")
    expect(await this.bar.balanceOf(this.alice.address)).to.equal("95000000000000000000")
  })

  it("should not allow withraw more than what you have", async function () {
    await this.joe.connect(this.alice).approve(this.bar.address, "100000000000000000000")
    await this.bar.connect(this.alice).enter("100000000000000000000")
    await expect(this.bar.connect(this.alice).leave("200000000000000000000")).to.be.revertedWith("ERC20: burn amount exceeds balance")
  })

  it("should work with more than one participant", async function () {
    await this.joe.connect(this.alice).approve(this.bar.address, "100000000000000000000")
    await this.joe.connect(this.bob).approve(this.bar.address, "100000000000000000000", { from: this.bob.address })
    // Alice enters and gets 20 shares. Bob enters and gets 10 shares.
    await this.bar.connect(this.alice).enter("20000000000000000000")
    await this.bar.connect(this.bob).enter("10000000000000000000", { from: this.bob.address })
    expect(await this.bar.balanceOf(this.alice.address)).to.equal("19000000000000000000")
    expect(await this.bar.balanceOf(this.bob.address)).to.equal("9499999954813546638")
    expect(await this.joe.balanceOf(this.bar.address)).to.equal("28500000090372907153")

    await this.joe.connect(this.carol).transfer(this.bar.address, "20000000000000000000", { from: this.carol.address })

    await this.bar.connect(this.alice).enter("10000000000000000000")
    expect(await this.bar.balanceOf(this.alice.address)).to.equal("24582474176344556984")
    expect(await this.bar.balanceOf(this.bob.address)).to.equal("9499999954813546638")

    await this.bar.connect(this.bob).leave("5000000000000000000", { from: this.bob.address })
    expect(await this.bar.balanceOf(this.alice.address)).to.equal("24582474176344556984")
    expect(await this.bar.balanceOf(this.bob.address)).to.equal("4499999954813546638")
    expect(await this.joe.balanceOf(this.bar.address)).to.equal("49491228493086794194")
    expect(await this.joe.balanceOf(this.alice.address)).to.equal("70000000000000000000")
    expect(await this.joe.balanceOf(this.bob.address)).to.equal("98508772030517058737")
  })

  describe("Rewarder", function () {
    it("Should allow enter, leave and claiming rewards each time", async function () {
      await this.joe.connect(this.alice).approve(this.bar.address, "1000000000000000000000")
      await this.bar.connect(this.alice).enter("100000000000000000000")
      expect(await this.bar.balanceOf(this.alice.address)).to.equal("95000000000000000000")
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("95000000000000000000")

      await increase(duration.days(365))

      await this.bar.connect(this.alice).leave("47500000000000000000")
      expect(await this.bar.balanceOf(this.alice.address)).to.equal("47500000000000000000")
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("50000000000000000000")
      expect(await this.joe.balanceOf(this.alice.address)).to.equal("50000000000000000000")
      expect((await this.rewarder.unpaidRewards()) - 1).to.be.greaterThan(0)

      await this.joe.connect(this.bob).transfer(this.rewarder.address, "100000000000000000000") // top up rewarder
      await this.bar.connect(this.alice).enter("50000000000000000000")
      expect(await this.rewarder.unpaidRewards()).to.be.equal("0")

      await this.bar.connect(this.alice).leave(await this.bar.balanceOf(this.alice.address))
      expect(await this.bar.balanceOf(this.alice.address)).to.equal("0")
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("0")
      expect((await this.joe.balanceOf(this.alice.address)) - 1).to.be.greaterThan(Number("100000000000000000000"))
      expect(await this.rewarder.unpaidRewards()).to.be.equal("0")
    })

    it("should allow emergency withdraw", async function () {
      const bal = await this.joe.balanceOf(this.rewarder.address)
      await this.rewarder.connect(this.dev).emergencyWithdraw()
      expect(await this.joe.balanceOf(this.rewarder.address)).to.equal("0")
      expect(await this.joe.balanceOf(this.dev.address)).to.equal(bal)
    })

    it("should increase unpaid reward", async function () {
      await this.joe.connect(this.alice).approve(this.bar.address, "1000000000000000000000")
      await this.bar.connect(this.alice).enter("100000000000000000000")

      await increase(duration.days(1))

      const unpaidReward = await this.rewarder.unpaidRewards()

      await increase(duration.days(1))

      await this.rewarder.update()
      expect((await this.rewarder.unpaidRewards()) - unpaidReward).to.be.greaterThan(0)
    })

    it("should revert on claim rewards from any other address than bar", async function () {
      await expect(this.rewarder.connect(this.dev).claimReward()).to.be.revertedWith("onlyBar: only JoeBar can call this function")
      await expect(this.rewarder.connect(this.alice).claimReward()).to.be.revertedWith("onlyBar: only JoeBar can call this function")
    })

    it("set apr", async function () {
      await this.rewarder.connect(this.dev).setApr("2000")
      await expect(this.rewarder.connect(this.alice).setApr("999999999999")).to.be.revertedWith("Ownable: caller is not the owner")
      expect(await this.rewarder.apr()).to.be.equal("2000")
    })
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
