import { ethers, network } from "hardhat"
import { expect } from "chai"
import { ADDRESS_ZERO, advanceTimeAndBlock, advanceBlockTo, latest, duration, increase } from "./utilities"

describe("MasterChefJoeV2", function () {
  before(async function () {
    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]
    this.bob = this.signers[1]
    this.carol = this.signers[2]
    this.dev = this.signers[3]
    this.treasury = this.signers[4]
    this.investor = this.signers[5]
    this.minter = this.signers[6]

    this.MCV2 = await ethers.getContractFactory("MasterChefJoeV2")
    this.MCV3 = await ethers.getContractFactory("MasterChefJoeV3")
    this.SimpleRewarderPerSec = await ethers.getContractFactory("SimpleRewarderPerSec")

    this.JoeToken = await ethers.getContractFactory("JoeToken")
    this.ERC20Mock = await ethers.getContractFactory("ERC20Mock", this.minter)
    this.SushiToken = await ethers.getContractFactory("SushiToken")

    this.devPercent = 200
    this.treasuryPercent = 200
    this.investorPercent = 100
    this.lpPercent = 1000 - this.devPercent - this.treasuryPercent - this.lpPercent
    this.joePerSec = 100
    this.secOffset = 1
    this.tokenOffset = 1
    this.reward = (sec: number, percent: number) => (sec * this.joePerSec * percent) / 1000

    // Rewarder parameters
    this.rewarderPerSec = 40
  })

  beforeEach(async function () {
    this.joe = await this.JoeToken.deploy() // b=1
    await this.joe.deployed()

    this.sushi = await this.SushiToken.deploy() // b=2
    await this.sushi.deployed()
  })

  it("should set joePerSec correctly", async function () {
    this.chef2 = await this.MCV2.deploy(
      this.joe.address,
      this.dev.address,
      this.treasury.address,
      this.investor.address,
      this.joePerSec,
      0,
      this.devPercent,
      this.treasuryPercent,
      this.investorPercent
    )
    await this.chef2.deployed()

    await this.joe.transferOwnership(this.chef2.address)

    this.dummyToken = await this.ERC20Mock.connect(this.alice).deploy("Joe Dummy", "DUMMY", 1)
    await this.chef2.add("100", this.dummyToken.address, ADDRESS_ZERO)

    this.chef3 = await this.MCV3.deploy(this.chef2.address, this.joe.address, 0)
    await this.chef3.deployed()

    await this.dummyToken.approve(this.chef3.address, 1)
    await this.chef3.init(this.dummyToken.address)
    expect(await this.chef3.joePerSec()).to.equal(50)

    await this.chef2.add("900", this.sushi.address, ADDRESS_ZERO)
    expect(await this.chef3.joePerSec()).to.equal(5)
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
