import { ethers, network, upgrades } from "hardhat"
import { expect } from "chai"
import { ADDRESS_ZERO, advanceBlock, advanceBlockTo, latest, duration, increase } from "./utilities"

describe("BoostedMasterChefJoe", function () {
  before(async function () {
    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]
    this.bob = this.signers[1]
    this.carol = this.signers[2]
    this.dev = this.signers[3]
    this.treasury = this.signers[4]
    this.investor = this.signers[5]
    this.minter = this.signers[6]

    this.MCV2 = await ethers.getContractFactory("MasterChefJoeV2", this.dev)
    this.BMC = await ethers.getContractFactory("BoostedMasterChefJoe", this.dev)

    this.JoeToken = await ethers.getContractFactory("JoeToken")
    this.VeJoeToken = await ethers.getContractFactory("VeJoeToken")
    this.ERC20Mock = await ethers.getContractFactory("ERC20Mock", this.minter)
    this.SushiToken = await ethers.getContractFactory("SushiToken")

    this.devPercent = 200
    this.treasuryPercent = 200
    this.investorPercent = 100
    this.lpPercent = 1000 - this.devPercent - this.treasuryPercent - this.lpPercent
    this.joePerSec = 100
    this.secOffset = 1
    this.tokenOffset = 1
  })

  beforeEach(async function () {
    this.joe = await this.JoeToken.deploy()
    await this.joe.deployed()
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
    this.dummyToken = await this.ERC20Mock.connect(this.dev).deploy("Joe Dummy", "DUMMY", 1)
    this.veJoe = await this.VeJoeToken.connect(this.dev).deploy()
    await this.chef2.add(100, this.dummyToken.address, ADDRESS_ZERO)

    this.bmc = await upgrades.deployProxy(this.BMC, [this.chef2.address, this.joe.address, this.veJoe.address, 0])
    await this.bmc.deployed()

    await this.veJoe.connect(this.dev).setBoostedMasterChefJoe(this.bmc.address)

    await this.dummyToken.connect(this.dev).approve(this.bmc.address, 1)
    expect(await this.bmc.connect(this.dev).init(this.dummyToken.address))
      .to.emit(this.bmc, "Init")
      .withArgs(1)

    this.lp = await this.ERC20Mock.deploy("LPToken", "LP", 10000000000)
    await this.lp.deployed()
    await this.lp.transfer(this.alice.address, 1000)
    await this.lp.transfer(this.bob.address, 1000)
    await this.lp.transfer(this.carol.address, 1000)

    await this.bmc.connect(this.dev).add(100, 5000, this.lp.address, ADDRESS_ZERO)
  })

  it("should revert if init called twice", async function () {
    await this.dummyToken.connect(this.dev).approve(this.bmc.address, 1)
    expect(this.bmc.connect(this.dev).init(this.dummyToken.address)).to.be.revertedWith(
      "BoostedMasterChefJoe: Already has a balance of dummy token"
    )
  })

  it("should adjust total factor when deposit", async function () {
    let pool
    // User has no veJoe
    await this.lp.connect(this.alice).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.alice).deposit(0, 1000)
    pool = await this.bmc.poolInfo(0)
    expect(pool.totalFactor).to.equal(0)
    expect(pool.totalLpSupply).to.equal(1000)
    expect((await this.bmc.userInfo(0, this.alice.address)).factor).to.equal(0)

    // Transfer some vejoe to bob
    await this.veJoe.connect(this.dev).mint(this.bob.address, 1000)

    // Bob enters the pool
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.bob).deposit(0, 1000)
    pool = await this.bmc.poolInfo(0)
    expect(pool.totalFactor).to.equal(1000)
    expect(pool.totalLpSupply).to.equal(2000)
    expect((await this.bmc.userInfo(0, this.bob.address)).factor).to.equal(1000)
  })

  it("should adjust factor balance when deposit first", async function () {
    // Transfer some vejoe to bob
    await this.veJoe.connect(this.dev).mint(this.bob.address, 100)

    // Bob enters the pool
    await this.lp.connect(this.bob).approve(this.bmc.address, 100)
    await this.bmc.connect(this.bob).deposit(0, 100)
    const pool = await this.bmc.poolInfo(0)
    expect(pool.totalFactor).to.equal(100)
    expect(pool.totalLpSupply).to.equal(100)
    expect((await this.bmc.userInfo(0, this.bob.address)).factor).to.equal(100)
  })

  it("should adjust factor balance on second deposit", async function () {
    let pool
    // Transfer some vejoe to bob
    await this.veJoe.connect(this.dev).mint(this.bob.address, 1000)
    // Bob enters the pool
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.bob).deposit(0, 10)
    pool = await this.bmc.poolInfo(0)
    expect(pool.totalLpSupply).to.equal(10)
    expect(pool.totalFactor).to.equal(100)
    expect((await this.bmc.userInfo(0, this.bob.address)).factor).to.equal(100)

    await this.bmc.connect(this.bob).deposit(0, 990)
    pool = await this.bmc.poolInfo(0)
    expect(pool.totalFactor).to.equal(1000)
    expect(pool.totalLpSupply).to.equal(1000)
    expect((await this.bmc.userInfo(0, this.bob.address)).factor).to.equal(1000)
  })

  it("should adjust boost balance when withdraw", async function () {
    await this.lp.connect(this.alice).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.alice).deposit(0, 1000)
    // Transfer some vejoe to bob
    await this.veJoe.connect(this.dev).mint(this.bob.address, 10)
    // Bob enters the pool
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.bob).deposit(0, 1000)

    await this.bmc.connect(this.bob).withdraw(0, 1000)
    const pool = await this.bmc.poolInfo(0)
    expect(pool.totalFactor).to.equal(0)
    expect(pool.totalLpSupply).to.equal(1000)
  })

  it("should adjust boost balance when partial withdraw", async function () {
    await this.lp.connect(this.alice).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.alice).deposit(0, 1000)
    // Transfer some vejoe to bob
    await this.veJoe.connect(this.dev).mint(this.bob.address, 10)
    // Bob enters the pool
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.bob).deposit(0, 1000)

    await this.bmc.connect(this.bob).withdraw(0, 990)
    const pool = await this.bmc.poolInfo(0)
    expect(pool.totalFactor).to.equal(10)
    expect(pool.totalLpSupply).to.equal(1010)
  })

  it("should return correct pending tokens according to boost", async function () {
    await this.veJoe.connect(this.dev).mint(this.bob.address, 100)
    // Disable automining so both users can deposit at the same time.
    await network.provider.send("evm_setAutomine", [false])

    await this.lp.connect(this.alice).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.alice).deposit(0, 1000)
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.bob).deposit(0, 1000)

    await advanceBlock()

    // Make sure contract has JOE to emit
    await this.bmc.connect(this.dev).harvestFromMasterChef()

    await increase(duration.hours(1))

    // bob should have 2.5x the pending tokens as alice.
    const alicePending = await this.bmc.pendingTokens(0, this.alice.address)
    const bobPending = await this.bmc.pendingTokens(0, this.bob.address)
    // Bob receives the same amount of JOE from alice, and all the veJoe side
    await expect(alicePending[0].add(alicePending[0] * 2)).to.be.closeTo(bobPending[0], 10)

    // Re-enable automining.
    await network.provider.send("evm_setAutomine", [true])
  })

  it("should record the correct reward debt on withdraw", async function () {
    await this.veJoe.connect(this.dev).mint(this.bob.address, 100)
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)

    await network.provider.send("evm_setAutomine", [false])
    await this.bmc.connect(this.bob).deposit(0, 1000)
    // Make sure contract has JOE to emit
    await this.bmc.connect(this.dev).harvestFromMasterChef()
    await increase(duration.hours(1))

    await this.bmc.connect(this.bob).withdraw(0, 0)
    await increase(duration.seconds(1))

    const user = await this.bmc.userInfo(0, this.bob.address)
    expect(await this.joe.balanceOf(this.bob.address)).to.equal(user.rewardDebt)

    await network.provider.send("evm_setAutomine", [true])
  })

  it("should claim reward on deposit", async function () {
    await this.veJoe.connect(this.dev).mint(this.bob.address, 1000)
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.bob).deposit(0, 10)

    await increase(duration.hours(1))

    await this.bmc.connect(this.dev).harvestFromMasterChef()
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.bob).deposit(0, 10)

    expect((await this.joe.balanceOf(this.bob.address)).gt(0)).to.be.true
  })

  it("should change rate when vjoe mints", async function () {
    let pool
    await this.lp.connect(this.alice).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.alice).deposit(0, 1000)
    pool = await this.bmc.poolInfo(0)
    expect(pool.totalFactor).to.equal(0)
    expect(pool.totalLpSupply).to.equal(1000)
    expect((await this.bmc.userInfo(0, this.alice.address)).factor).to.equal(0)

    // Bob enters the pool
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.bob).deposit(0, 1000)
    pool = await this.bmc.poolInfo(0)
    expect(pool.totalFactor).to.equal(0)
    expect(pool.totalLpSupply).to.equal(2000)
    expect((await this.bmc.userInfo(0, this.bob.address)).factor).to.equal("0")

    // Mint some vejoe to bob
    await this.veJoe.connect(this.dev).mint(this.bob.address, 10)
    pool = await this.bmc.poolInfo(0)
    expect(pool.totalFactor).to.equal(100)
    expect(pool.totalLpSupply).to.equal(2000)
    expect((await this.bmc.userInfo(0, this.bob.address)).factor).to.equal(100)
  })

  it("should change rate when vjoe burns", async function () {
    let pool
    await this.lp.connect(this.alice).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.alice).deposit(0, 1000)
    pool = await this.bmc.poolInfo(0)
    expect(pool.totalFactor).to.equal(0)
    expect(pool.totalLpSupply).to.equal(1000)
    expect((await this.bmc.userInfo(0, this.alice.address)).factor).to.equal(0)

    // Bob enters the pool
    await this.veJoe.connect(this.dev).mint(this.bob.address, 10)
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.bob).deposit(0, 1000)
    pool = await this.bmc.poolInfo(0)
    expect(pool.totalFactor).to.equal(100)
    expect(pool.totalLpSupply).to.equal(2000)
    expect((await this.bmc.userInfo(0, this.bob.address)).factor).to.equal(100)

    await this.veJoe.connect(this.dev).burnFrom(this.bob.address, 10)

    pool = await this.bmc.poolInfo(0)
    expect(pool.totalFactor).to.equal(0)
    expect(pool.totalLpSupply).to.equal(2000)
    expect((await this.bmc.userInfo(0, this.bob.address)).factor).to.equal("0")
  })

  it("should pay out rewards in claimable", async function () {
    // Bob enters the pool

    await this.veJoe.connect(this.dev).mint(this.bob.address, 10)
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.bob).deposit(0, 1000)

    await increase(duration.hours(1))

    const pending = await this.bmc.pendingTokens(0, this.bob.address)
    expect(pending[0].gt(0)).to.be.true

    await this.veJoe.connect(this.dev).mint(this.bob.address, 10)
    let claimable = await this.bmc.claimableJoe(0, this.bob.address)
    // Close to as 1 second passes after the mint.
    expect(pending[0]).to.be.closeTo(claimable, 100)

    await this.bmc.connect(this.bob).withdraw(0, 0)
    expect(await this.bmc.claimableJoe(0, this.bob.address)).to.equal(0)
    expect(await this.joe.balanceOf(this.bob.address)).to.be.closeTo(pending[0], 100)
  })

  it("should stop boosting if burn vejoe", async function () {
    // Bob enters the pool
    await this.veJoe.connect(this.dev).mint(this.bob.address, 10)
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.bob).deposit(0, 1000)

    await increase(duration.hours(1))

    let user
    user = await this.bmc.userInfo(0, this.bob.address)
    expect(user.factor).to.equal(100)

    await this.veJoe.connect(this.dev).burnFrom(this.bob.address, 10)
    user = await this.bmc.userInfo(0, this.bob.address)
    expect(user.factor).to.equal(0)

    let pending = await this.bmc.pendingTokens(0, this.bob.address)
    let claimable = await this.bmc.claimableJoe(0, this.bob.address)
    // Close to as 1 second passes after the mint.
    expect(pending[0]).to.be.closeTo(claimable, 100)
  })

  it("it should update the totalAllocPoint when calling set", async function () {
    await this.bmc.set(0, 1000, 4000, ADDRESS_ZERO, 0)
    expect(await this.bmc.totalAllocPoint()).to.equal(1000)
    expect((await this.bmc.poolInfo(0)).allocPoint).to.equal(1000)
  })

  it("it should never decrease pending tokens", async function () {
    await this.veJoe.connect(this.dev).mint(this.bob.address, 100)
    await this.lp.connect(this.bob).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.bob).deposit(0, 1000)

    await increase(duration.hours(24))
    await advanceBlock()
    const pending0 = await this.bmc.pendingTokens(0, this.bob.address)

    await this.veJoe.connect(this.dev).mint(this.alice.address, 100)
    await this.lp.connect(this.alice).approve(this.bmc.address, 1000)
    await this.bmc.connect(this.alice).deposit(0, 1000)

    const pending1 = await this.bmc.pendingTokens(0, this.bob.address)

    expect(pending1[0] > pending0[0]).to.be.true
  })

  it("bug ackee script 1", async function () {
    const lp2 = await this.ERC20Mock.deploy("LPToken", "LP", 10000000000)
    await lp2.deployed()
    await lp2.transfer(this.bob.address, 1000)

    await this.bmc.connect(this.dev).add(100, 0, lp2.address, ADDRESS_ZERO)

    await this.lp.connect(this.alice).approve(this.bmc.address, 1000)
    await lp2.connect(this.bob).approve(this.bmc.address, 1000)

    await this.bmc.connect(this.alice).deposit(0, 1000)
    await this.bmc.connect(this.bob).deposit(1, 1000)

    await increase(duration.hours(24))
    await advanceBlock()

    await this.bmc.updatePool(1)
    await this.bmc.set(0, 900, 0, ADDRESS_ZERO, false)

    await this.bmc.connect(this.alice).deposit(0, 0)
    await this.bmc.connect(this.bob).deposit(1, 0)
    await this.bmc.connect(this.alice).withdraw(0, 0)
    await this.bmc.connect(this.bob).withdraw(1, 0)
  })

  it("it should allow deposits if contract has balance", async function () {
    await this.lp.transfer(this.bmc.address, 100)
    await this.bmc.updatePool(0)
    await this.lp.connect(this.bob).approve(this.bmc.address, 100)
    await this.bmc.connect(this.bob).deposit(0, 100)
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
