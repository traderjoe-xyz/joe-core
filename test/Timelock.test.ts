import { ethers, network } from "hardhat"
import { expect } from "chai"
import { encodeParameters, latest, duration, increase } from "./utilities"

describe("Timelock", function () {
  before(async function () {
    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]
    this.bob = this.signers[1]
    this.carol = this.signers[2]
    this.dev = this.signers[3]
    this.treasury = this.signers[4]
    this.minter = this.signers[5]

    this.JoeToken = await ethers.getContractFactory("JoeToken")
    this.Timelock = await ethers.getContractFactory("Timelock")
    this.ERC20Mock = await ethers.getContractFactory("ERC20Mock", this.minter)
    this.MasterChef = await ethers.getContractFactory("MasterChefJoe")
  })

  beforeEach(async function () {
    this.joe = await this.JoeToken.deploy()
    this.timelock = await this.Timelock.deploy(this.bob.address, "259200")
  })

  it("should not allow non-owner to do operation", async function () {
    await this.joe.transferOwnership(this.timelock.address)
    // await expectRevert(this.joe.transferOwnership(carol, { from: alice }), "Ownable: caller is not the owner")

    await expect(this.joe.transferOwnership(this.carol.address)).to.be.revertedWith("Ownable: caller is not the owner")
    await expect(this.joe.connect(this.bob).transferOwnership(this.carol.address)).to.be.revertedWith("Ownable: caller is not the owner")

    await expect(
      this.timelock.queueTransaction(
        this.joe.address,
        "0",
        "transferOwnership(address)",
        encodeParameters(["address"], [this.carol.address]),
        (await latest()).add(duration.days(4))
      )
    ).to.be.revertedWith("Timelock::queueTransaction: Call must come from admin.")
  })

  it("should do the timelock thing", async function () {
    await this.joe.transferOwnership(this.timelock.address)
    const eta = (await latest()).add(duration.days(4))
    await this.timelock
      .connect(this.bob)
      .queueTransaction(this.joe.address, "0", "transferOwnership(address)", encodeParameters(["address"], [this.carol.address]), eta)
    await increase(duration.days(1))
    await expect(
      this.timelock
        .connect(this.bob)
        .executeTransaction(this.joe.address, "0", "transferOwnership(address)", encodeParameters(["address"], [this.carol.address]), eta)
    ).to.be.revertedWith("Timelock::executeTransaction: Transaction hasn't surpassed time lock.")
    await increase(duration.days(4))
    await this.timelock
      .connect(this.bob)
      .executeTransaction(this.joe.address, "0", "transferOwnership(address)", encodeParameters(["address"], [this.carol.address]), eta)
    expect(await this.joe.owner()).to.equal(this.carol.address)
  })

  it("should also work with MasterChefJoe", async function () {
    this.lp1 = await this.ERC20Mock.deploy("LPToken", "LP", "10000000000")
    this.lp2 = await this.ERC20Mock.deploy("LPToken", "LP", "10000000000")
    this.chef = await this.MasterChef.deploy(this.joe.address, this.dev.address, this.treasury.address, "100", "0", "200", "200")
    await this.joe.transferOwnership(this.chef.address)
    await this.chef.add("100", this.lp1.address)
    await this.chef.transferOwnership(this.timelock.address)
    const eta = (await latest()).add(duration.days(4))
    await this.timelock
      .connect(this.bob)
      .queueTransaction(this.chef.address, "0", "set(uint256,uint256)", encodeParameters(["uint256", "uint256"], ["0", "200"]), eta)
    await this.timelock
      .connect(this.bob)
      .queueTransaction(this.chef.address, "0", "add(uint256,address)", encodeParameters(["uint256", "address"], ["100", this.lp2.address]), eta)
    await increase(duration.days(4))
    await this.timelock
      .connect(this.bob)
      .executeTransaction(this.chef.address, "0", "set(uint256,uint256)", encodeParameters(["uint256", "uint256"], ["0", "200"]), eta)
    await this.timelock
      .connect(this.bob)
      .executeTransaction(
        this.chef.address,
        "0",
        "add(uint256,address)",
        encodeParameters(["uint256", "address"], ["100", this.lp2.address]),
        eta
      )
    expect((await this.chef.poolInfo("0")).allocPoint).to.equal("200")
    expect(await this.chef.totalAllocPoint()).to.equal("300")
    expect(await this.chef.poolLength()).to.equal("2")
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
