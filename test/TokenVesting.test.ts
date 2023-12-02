import { ethers, network } from "hardhat"
import { expect } from "chai"
import { duration, increase } from "./utilities"

const ONE_WEEK = 604800

const CLIFF_LENGTH = ONE_WEEK
const DURATION = 2 * ONE_WEEK

describe.only("TokenVesting", function () {
  let blockTimestamp

  before(async function () {
    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]

    this.JoeToken = await ethers.getContractFactory("JoeToken")
    this.TokenVesting = await ethers.getContractFactory("TokenVesting")
  })

  beforeEach(async function () {
    blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp
    this.joe = await this.JoeToken.deploy()
    this.tokenVesting = await this.TokenVesting.deploy(this.alice.address, blockTimestamp, CLIFF_LENGTH, DURATION, true)
    this.joe.mint(this.tokenVesting.address, 100)
  })

  it("should only allow release of tokens once cliff is passed", async function () {
    await expect(this.tokenVesting.release(this.joe.address)).to.be.revertedWith("TokenVesting: no tokens are due")
    await increase(duration.days(6))
    await expect(this.tokenVesting.release(this.joe.address)).to.be.revertedWith("TokenVesting: no tokens are due")
    await increase(duration.days(1))
    await this.tokenVesting.release(this.joe.address)
    expect(await this.joe.balanceOf(this.alice.address)).to.gt(0)
    expect(await this.joe.balanceOf(this.tokenVesting.address)).to.lt(100)
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
