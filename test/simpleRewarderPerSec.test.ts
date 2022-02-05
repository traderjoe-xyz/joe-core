// @ts-ignore
import { ethers, network } from "hardhat"
import { expect } from "chai"
import { duration, increase } from "./utilities"

const hre = require("hardhat")

const WAVAX_ADDRESS = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7"
const UST_ADDRESS = "0x260Bbf5698121EB85e7a74f2E45E16Ce762EbE11"
const LUNA_ADDRESS = "0x120AD3e5A7c796349e591F1570D9f7980F4eA9cb"

const USTWAVAX_ADDRESS = "0x7bf98bd74e19ad8eb5e14076140ee0103f8f872b"

const SIMPLE_REWARDER_LUNAWAVAX_ADDRESS = "0xB8cFb907e3a41A5af5a40CAACBC1745e0CC829f5"
const MCV3_ADDRESS = "0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00"

describe.only("simple rewarder per seconds", function () {
  before(async function () {
    // Forking main net
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: "https://api.avax.network/ext/bc/C/rpc",
            blockNumber: 10500371,
          },
          live: false,
          saveDeployments: true,
          tags: ["test", "local"],
        },
      ],
    })

    // ABIs
    let ERC20MockDecimalsCF = await ethers.getContractFactory("ERC20MockDecimals")
    let PairCF = await ethers.getContractFactory("JoePair")
    let MCV3CF = await ethers.getContractFactory("MasterChefJoeV3")
    this.simpleRewarderPerSecCF = await ethers.getContractFactory("SimpleRewarderPerSec")

    // Account
    const ownerAddress = "0x6B5732937e1c3B041B95D523C1817E45746d39C0"
    await hre.network.provider.request({ method: "hardhat_impersonateAccount", params: [ownerAddress] })
    this.owner = await ethers.getSigner(ownerAddress)

    // Contracts
    this.oldRewarder = await this.simpleRewarderPerSecCF.attach(SIMPLE_REWARDER_LUNAWAVAX_ADDRESS)
    this.MCV3 = await MCV3CF.attach(MCV3_ADDRESS)

    // Tokens
    this.wavax = await ethers.getContractAt("IWAVAX", WAVAX_ADDRESS, this.dev)
    this.ust = await ERC20MockDecimalsCF.attach(UST_ADDRESS)
    this.luna = await ERC20MockDecimalsCF.attach(LUNA_ADDRESS)
    this.joe = await ERC20MockDecimalsCF.deploy(18)
    this.token6D = await ERC20MockDecimalsCF.deploy(6)

    // Pairs
    this.ustWavax = await PairCF.attach(USTWAVAX_ADDRESS)
  })

  beforeEach(async function () {
    // We redeploy simpleRewarderPerSec for each tests
    this.simpleRewarderPerSec = await this.simpleRewarderPerSecCF.deploy(this.joe.address, USTWAVAX_ADDRESS, "450", this.MCV3.address, false)

    await this.token6D.mint(this.simpleRewarderPerSec.address, ethers.utils.parseUnits("1000", 6))
  })

  describe("Proof of Concept", function () {
    it("old rewarder rounds to 0", async function () {
      expect((await this.MCV3.poolInfo(45)).rewarder).to.be.equal(this.oldRewarder.address)

      await this.MCV3.withdraw(45, 0)
      let poolInfo = await this.oldRewarder.poolInfo()
      let accTokenPerShare = poolInfo.accTokenPerShare
      let lastRewardTimestamp = poolInfo.lastRewardTimestamp

      // We wait 5 minutes
      increase(duration.minutes(5))

      await this.MCV3.withdraw(45, 0)
      // accTokenPerShare is rounded to 0
      expect((await this.oldRewarder.poolInfo())[0]).to.be.equal(accTokenPerShare)
      expect((await this.oldRewarder.poolInfo())[1]).to.be.above(lastRewardTimestamp)
    })

    it("new rewarder fix this issue", async function () {
      await this.MCV3.connect(this.owner).set(45, "500", this.simpleRewarderPerSec.address, true)

      expect((await this.MCV3.poolInfo(45)).rewarder).to.be.equal(this.simpleRewarderPerSec.address)

      await this.MCV3.withdraw(45, 0)
      let poolInfo = await this.simpleRewarderPerSec.poolInfo()
      let accTokenPerShare = poolInfo.accTokenPerShare
      let lastRewardTimestamp = poolInfo.lastRewardTimestamp

      // We wait 1 second
      increase(duration.seconds(1))

      await this.MCV3.withdraw(45, 0)
      // accTokenPerShare is rounded to 0
      expect((await this.simpleRewarderPerSec.poolInfo())[0]).to.be.above(accTokenPerShare)
      expect((await this.simpleRewarderPerSec.poolInfo())[1]).to.be.above(lastRewardTimestamp)
    })
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
