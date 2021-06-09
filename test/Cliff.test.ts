import { ethers, network } from "hardhat"
import { expect } from "chai"
import { duration, increase } from "./utilities"

describe("Cliff", function () {
  before(async function () {
    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]

    this.JoeToken = await ethers.getContractFactory("JoeToken")
    this.Cliff = await ethers.getContractFactory("Cliff")
  })

  beforeEach(async function () {
    this.joe = await this.JoeToken.deploy()
    this.cliff = await this.Cliff.deploy(this.joe.address, this.alice.address, 0, 3)
    this.joe.mint(this.cliff.address, 100)
  })

  it("should only allow release of tokens once cliff is passed", async function () {
    await expect(this.cliff.release()).to.be.revertedWith("Cliff: No tokens to release")
    await increase(duration.days(89))
    await expect(this.cliff.release()).to.be.revertedWith("Cliff: No tokens to release")
    await increase(duration.days(1))
    await this.cliff.release()
    expect(await this.joe.balanceOf(this.alice.address)).to.equal(100)
    expect(await this.joe.balanceOf(this.cliff.address)).to.equal(0)

    await this.joe.mint(this.cliff.address, 500)
    await this.cliff.release()
    expect(await this.joe.balanceOf(this.alice.address)).to.equal(600)
    expect(await this.joe.balanceOf(this.cliff.address)).to.equal(0)
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
