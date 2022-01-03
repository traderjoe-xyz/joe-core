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

    this.rewarder = await this.BarRewarder.deploy(this.joe.address, "1500")

    this.bar = await hre.upgrades.deployProxy(this.JoeBarV2, [this.joe.address, this.rewarder.address, "500"])

    await this.bar.setRewarder(this.rewarder.address)
    await this.joe.mint(this.alice.address, ethers.utils.parseEther("100"))
    await this.joe.mint(this.bob.address, ethers.utils.parseEther("100"))
    await this.joe.mint(this.carol.address, ethers.utils.parseEther("100"))
  })

  it("should allow to set entryFee from owner only", async function () {
    await this.bar.connect(this.dev).setEntryFee("5000")

    await expect(this.bar.connect(this.dev).setEntryFee("5001")).to.be.revertedWith("JoeBarV2: entryFee too high")

    await expect(this.bar.connect(this.alice).setEntryFee("0")).to.be.revertedWith("Ownable: caller is not the owner")
    expect(await this.bar.entryFee()).to.be.equal("5000")
  })

  it("should not allow enter if not enough approve", async function () {
    await expect(this.bar.connect(this.alice).enter(ethers.utils.parseEther("100"))).to.be.revertedWith(
      "ERC20: transfer amount exceeds allowance"
    )
    await this.joe.connect(this.alice).approve(this.bar.address, ethers.utils.parseEther("50"))
    await expect(this.bar.connect(this.alice).enter(ethers.utils.parseEther("100"))).to.be.revertedWith(
      "ERC20: transfer amount exceeds allowance"
    )
    await this.joe.connect(this.alice).approve(this.bar.address, ethers.utils.parseEther("100"))
    await this.bar.connect(this.alice).enter(ethers.utils.parseEther("100"))
    expect(await this.bar.balanceOf(this.alice.address)).to.equal(ethers.utils.parseEther("95"))
  })

  it("should not allow withraw more than what you have", async function () {
    await this.joe.connect(this.alice).approve(this.bar.address, ethers.utils.parseEther("100"))
    await this.bar.connect(this.alice).enter(ethers.utils.parseEther("100"))
    await expect(this.bar.connect(this.alice).leave(ethers.utils.parseEther("95.00000000000000001"))).to.be.revertedWith(
      "ERC20: burn amount exceeds balance"
    )
  })

  it("should work with more than one participant", async function () {
    await this.joe.connect(this.alice).approve(this.bar.address, ethers.utils.parseEther("100"))
    await this.joe.connect(this.bob).approve(this.bar.address, ethers.utils.parseEther("100"), { from: this.bob.address })
    // Alice enters and gets 20 shares. Bob enters and gets 10 shares.
    await this.bar.connect(this.alice).enter(ethers.utils.parseEther("20"))
    await this.bar.connect(this.bob).enter(ethers.utils.parseEther("10"), { from: this.bob.address })
    expect(await this.bar.balanceOf(this.alice.address)).to.equal(ethers.utils.parseEther("19"))
    expect(await this.bar.balanceOf(this.bob.address)).to.equal(ethers.utils.parseEther("9.499999954813546638"))
    expect(await this.joe.balanceOf(this.bar.address)).to.equal(ethers.utils.parseEther("28.500000090372907153"))

    await this.joe.connect(this.carol).transfer(this.bar.address, ethers.utils.parseEther("20"), { from: this.carol.address })

    await this.bar.connect(this.alice).enter(ethers.utils.parseEther("10"))
    expect(await this.bar.balanceOf(this.alice.address)).to.equal(ethers.utils.parseEther("24.582474176344556984"))
    expect(await this.bar.balanceOf(this.bob.address)).to.equal(ethers.utils.parseEther("9.499999954813546638"))

    await this.bar.connect(this.bob).leave("5000000000000000000", { from: this.bob.address })
    expect(await this.bar.balanceOf(this.alice.address)).to.equal(ethers.utils.parseEther("24.582474176344556984"))
    expect(await this.bar.balanceOf(this.bob.address)).to.equal(ethers.utils.parseEther("4.499999954813546638"))
    expect(await this.joe.balanceOf(this.bar.address)).to.equal(ethers.utils.parseEther("49.491228493086794194"))
    expect(await this.joe.balanceOf(this.alice.address)).to.equal(ethers.utils.parseEther("70"))
    expect(await this.joe.balanceOf(this.bob.address)).to.equal(ethers.utils.parseEther("98.508772030517058737"))
  })

  describe("Rewarder", function () {
    it("Should allow enter, leave and claiming rewards each time", async function () {
      await this.joe.connect(this.alice).approve(this.bar.address, ethers.utils.parseEther("1000"))
      await this.bar.connect(this.alice).enter(ethers.utils.parseEther("100"))
      expect(await this.bar.balanceOf(this.alice.address)).to.equal(ethers.utils.parseEther("95"))
      expect(await this.joe.balanceOf(this.bar.address)).to.equal(ethers.utils.parseEther("95"))

      await increase(duration.days(365))

      await this.bar.connect(this.alice).leave(ethers.utils.parseEther("47.5"))
      expect(await this.bar.balanceOf(this.alice.address)).to.equal(ethers.utils.parseEther("47.5"))
      expect(await this.joe.balanceOf(this.bar.address)).to.equal(ethers.utils.parseEther("50"))
      expect(await this.joe.balanceOf(this.alice.address)).to.equal(ethers.utils.parseEther("50"))
      expect((await this.rewarder.unpaidRewards()) - 1).to.be.greaterThan(0)

      await this.joe.connect(this.bob).transfer(this.rewarder.address, ethers.utils.parseEther("100")) // top up rewarder
      await this.bar.connect(this.alice).enter(ethers.utils.parseEther("50"))
      expect(await this.rewarder.unpaidRewards()).to.be.equal("0")

      await this.bar.connect(this.alice).leave(await this.bar.balanceOf(this.alice.address))
      expect(await this.bar.balanceOf(this.alice.address)).to.equal("0")
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("0")
      expect((await this.joe.balanceOf(this.alice.address)) - 1).to.be.greaterThan(Number(ethers.utils.parseEther("100")))
      expect(await this.rewarder.unpaidRewards()).to.be.equal("0")
    })

    it("should allow emergency withdraw", async function () {
      const bal = await this.joe.balanceOf(this.rewarder.address)
      await this.rewarder.connect(this.dev).emergencyWithdraw()
      expect(await this.joe.balanceOf(this.rewarder.address)).to.equal("0")
      expect(await this.joe.balanceOf(this.dev.address)).to.equal(bal)
    })

    it("should increase unpaid reward", async function () {
      await this.joe.connect(this.alice).approve(this.bar.address, ethers.utils.parseEther("1000"))
      await this.bar.connect(this.alice).enter(ethers.utils.parseEther("100"))

      await increase(duration.days(1))

      const unpaidReward = await this.rewarder.unpaidRewards()

      await increase(duration.days(1))

      await this.rewarder.updateRewardVars()
      expect((await this.rewarder.unpaidRewards()) - unpaidReward).to.be.greaterThan(0)
    })

    it("should revert on claim rewards from any other address than bar", async function () {
      await expect(this.rewarder.connect(this.dev).claimReward()).to.be.revertedWith("onlyBar: only JoeBar can call this function")
      await expect(this.rewarder.connect(this.alice).claimReward()).to.be.revertedWith("onlyBar: only JoeBar can call this function")
    })

    it("set apr", async function () {
      await this.rewarder.connect(this.dev).setApr("2000")
      await expect(this.rewarder.connect(this.dev).setApr("10001")).to.be.revertedWith("BarRewarderPerSec: Apr can't be greater than 100%")
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
