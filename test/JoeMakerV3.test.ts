// @ts-ignore
import { ethers, network } from "hardhat"
import { expect } from "chai"
import { getBigNumber } from "./utilities"

const JOE_ADDRESS = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd"
const WAVAX_ADDRESS = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7"
const USDT_ADDRESS = "0xc7198437980c041c805A1EDcbA50c1Ce5db95118"
const USDC_ADDRESS = "0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664"
const DAI_ADDRESS = "0xd586E7F844cEa2F87f50152665BCbc2C279D8d70"
const WBTC_ADDRESS = "0x50b7545627a5162F82A992c33b87aDc75187B218"
const LINK_ADDRESS = "0x5947BB275c521040051D82396192181b413227A3"
const TRACTOR_ADDRESS = "0x542fA0B261503333B90fE60c78F2BeeD16b7b7fD"
const ROUTER_ADDRESS = "0x60aE616a2155Ee3d9A68541Ba4544862310933d4"

const JOEAVAX_ADDRESS = "0x454E67025631C065d3cFAD6d71E6892f74487a15"
const LINKAVAX_ADDRESS = "0x6F3a0C89f611Ef5dC9d96650324ac633D02265D3"
const DAIAVAX_ADDRESS = "0x87Dee1cC9FFd464B79e058ba20387c1984aed86a"
const USDCAVAX_ADDRESS = "0xa389f9430876455c36478deea9769b7ca4e3ddb1"
const TRACTORAVAX_ADDRESS = "0x601e0f63be88a52b79dbac667d6b4a167ce39113"
const LINKUSDC_ADDRESS = "0xb9f425bc9af072a91c423e31e9eb7e04f226b39d"
const JOEUSDT_ADDRESS = "0x1643de2efB8e35374D796297a9f95f64C082a8ce"
const USDCDAI_ADDRESS = "0x63ABE32d0Ee76C05a11838722A63e012008416E6"
const WBTCUSDC_ADDRESS = "0x62475f52add016a06b398aa3b2c2f2e540d36859"

const FACTORY_ADDRESS = "0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10"
const ZAP_ADDRESS = "0x2C7B8e971c704371772eDaf16e0dB381A8D02027"
const BAR_ADDRESS = "0x57319d41F71E81F3c65F2a47CA4e001EbAFd4F33"

// Test values in order to be sure JoeMakerV3 converts as much as JoeMakerV1
const barBalanceJOEAVAX = "67845624860978841228702792"
const barBalanceDAIUSDC = "67845624656456566165626771"

describe("joeMakerV3", function () {
  before(async function () {
    // ABIs
    this.joeMakerV3CF = await ethers.getContractFactory("JoeMakerV3")
    this.joeMakerCF = await ethers.getContractFactory("JoeMaker")
    this.ERC20CF = await ethers.getContractFactory("JoeERC20")
    this.ZapCF = await ethers.getContractFactory("Zap")
    this.PairCF = await ethers.getContractFactory("JoePair")
    this.RouterCF = await ethers.getContractFactory("JoeRouter02")

    // Account
    this.signers = await ethers.getSigners()
    this.dev = this.signers[0]
    this.alice = this.signers[1]

    // Contracts
    this.factory = await ethers.getContractAt("JoeFactory", FACTORY_ADDRESS)
    this.zap = await this.ZapCF.attach(ZAP_ADDRESS, this.dev)
    this.router = await this.RouterCF.attach(ROUTER_ADDRESS, this.dev)

    // Tokens
    this.wavax = await ethers.getContractAt("IWAVAX", WAVAX_ADDRESS, this.dev)
    this.joe = await this.ERC20CF.attach(JOE_ADDRESS)
    this.usdt = await this.ERC20CF.attach(USDT_ADDRESS)
    this.usdc = await this.ERC20CF.attach(USDC_ADDRESS)
    this.dai = await this.ERC20CF.attach(DAI_ADDRESS)
    this.link = await this.ERC20CF.attach(LINK_ADDRESS)
    this.wbtc = await this.ERC20CF.attach(WBTC_ADDRESS)
    this.tractor = await this.ERC20CF.attach(TRACTOR_ADDRESS)

    // Pairs
    this.joeAvax = await this.PairCF.attach(JOEAVAX_ADDRESS, this.dev)
    this.linkAvax = await this.PairCF.attach(LINKAVAX_ADDRESS, this.dev)
    this.daiAvax = await this.PairCF.attach(DAIAVAX_ADDRESS, this.dev)
    this.usdcAvax = await this.PairCF.attach(USDCAVAX_ADDRESS, this.dev)
    this.linkUsdc = await this.PairCF.attach(LINKUSDC_ADDRESS, this.dev)
    this.joeUsdt = await this.PairCF.attach(JOEUSDT_ADDRESS, this.dev)
    this.usdcDai = await this.PairCF.attach(USDCDAI_ADDRESS, this.dev)
    this.wbtcUsdc = await this.PairCF.attach(WBTCUSDC_ADDRESS, this.dev)
    this.tractorAvax = await this.PairCF.attach(TRACTORAVAX_ADDRESS, this.dev)
  })

  beforeEach(async function () {
    // We reset the state before each tests
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: "https://api.avax.network/ext/bc/C/rpc",
            blockNumber: 6394745,
          },
          live: false,
          saveDeployments: true,
          tags: ["test", "local"],
        },
      ],
    })

    // We redeploy JoeMakerV3 for each tests too
    this.joeMakerV3 = await this.joeMakerV3CF.deploy(FACTORY_ADDRESS, BAR_ADDRESS, JOE_ADDRESS, WAVAX_ADDRESS)
    await this.joeMakerV3.deployed()
  })

  describe("setBridge", function () {
    it("does not allow to set bridge for Joe", async function () {
      await expect(this.joeMakerV3.setBridge(this.joe.address, this.wavax.address)).to.be.revertedWith("JoeMakerV3: Invalid bridge")
    })

    it("does not allow to set bridge for WAVAX", async function () {
      await expect(this.joeMakerV3.setBridge(this.wavax.address, this.joe.address)).to.be.revertedWith("JoeMakerV3: Invalid bridge")
    })

    it("does not allow to set bridge to itself", async function () {
      await expect(this.joeMakerV3.setBridge(this.dai.address, this.dai.address)).to.be.revertedWith("JoeMakerV3: Invalid bridge")
    })

    it("emits correct event on bridge", async function () {
      await expect(this.joeMakerV3.setBridge(this.dai.address, this.joe.address))
        .to.emit(this.joeMakerV3, "LogBridgeSet")
        .withArgs(this.dai.address, this.joe.address)
    })
  })

  describe("convert", function () {
    it("should convert JOE - AVAX", async function () {
      await this.zap.zapIn(this.joeAvax.address, { value: "2000000000000000000" })
      await this.joeAvax.transfer(this.joeMakerV3.address, await this.joeAvax.balanceOf(this.dev.address))
      await this.joeMakerV3.convert(this.joe.address, this.wavax.address)
      expect(await this.joe.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.joeAvax.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal(barBalanceJOEAVAX)
    })

    it("should convert JOE - AVAX using JoeMakerV1 to make sure V3 converts as much as V1", async function () {
      this.joeMaker = await this.joeMakerCF.deploy(FACTORY_ADDRESS, BAR_ADDRESS, JOE_ADDRESS, WAVAX_ADDRESS)
      await this.joeMaker.deployed()

      await this.zap.zapIn(this.joeAvax.address, { value: "2000000000000000000" })
      await this.joeAvax.transfer(this.joeMaker.address, await this.joeAvax.balanceOf(this.dev.address))
      await this.joeMaker.convert(this.joe.address, this.wavax.address)
      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joeAvax.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal(barBalanceJOEAVAX)
    })

    it("should convert USDC - AVAX", async function () {
      await this.zap.zapIn(this.usdcAvax.address, { value: "2000000000000000000" })
      await this.usdcAvax.transfer(this.joeMakerV3.address, await this.usdcAvax.balanceOf(this.dev.address))
      await this.joeMakerV3.convert(this.usdc.address, this.wavax.address)
      expect(await this.joe.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.usdcAvax.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("67845624709410908108101276")
    })

    it("should convert LINK - AVAX", async function () {
      await this.zap.zapIn(this.linkAvax.address, { value: "2000000000000000000" })
      await this.linkAvax.transfer(this.joeMakerV3.address, await this.linkAvax.balanceOf(this.dev.address))
      await this.joeMakerV3.convert(this.link.address, this.wavax.address)
      expect(await this.joe.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.linkAvax.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("67845624709451838911952369")
    })

    it("reverts if convert is called by non auth", async function () {
      await this.zap.zapIn(this.joeAvax.address, { value: "2000000000000000000" })
      await this.joeAvax.transfer(this.joeMakerV3.address, await this.joeAvax.balanceOf(this.dev.address))
      await expect(this.joeMakerV3.connect(this.alice).convert(this.joe.address, this.wavax.address)).to.be.revertedWith("JoeMakerV3: FORBIDDEN")
    })

    it("should convert USDT - JOE", async function () {
      await this.zap.zapIn(this.joeUsdt.address, { value: "2000000000000000000" })
      await this.joeUsdt.transfer(this.joeMakerV3.address, await this.joeUsdt.balanceOf(this.dev.address))
      await this.joeMakerV3.convert(this.usdt.address, this.joe.address)
      expect(await this.joe.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.joeUsdt.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("67845624860644069497935644")
    })

    it("should convert using standard AVAX path", async function () {
      await this.zap.zapIn(this.daiAvax.address, { value: "2000000000000000000" })
      await this.daiAvax.transfer(this.joeMakerV3.address, await this.daiAvax.balanceOf(this.dev.address))
      await this.joeMakerV3.convert(this.dai.address, this.wavax.address)
      expect(await this.joe.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.daiAvax.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("67845624709488609524599005")
    })

    it("converts LINK/USDC using more complex path", async function () {
      await this.zap.zapIn(this.linkUsdc.address, { value: "2000000000000000000" })
      await this.linkUsdc.transfer(this.joeMakerV3.address, await this.linkUsdc.balanceOf(this.dev.address))
      await this.joeMakerV3.setBridge(this.usdt.address, this.joe.address)
      await this.joeMakerV3.setBridge(this.usdc.address, this.usdt.address)
      await this.joeMakerV3.convert(this.link.address, this.usdc.address)
      expect(await this.joe.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.linkUsdc.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("67845624540931902552332917")
    })

    it("converts DAI/USDC using more complex path", async function () {
      await this.zap.zapIn(this.usdcDai.address, { value: "2000000000000000000" })
      await this.usdcDai.transfer(this.joeMakerV3.address, await this.usdcDai.balanceOf(this.dev.address))
      await this.joeMakerV3.setBridge(this.usdc.address, this.joe.address)
      await this.joeMakerV3.setBridge(this.dai.address, this.usdc.address)
      await this.joeMakerV3.convert(this.dai.address, this.usdc.address)
      expect(await this.joe.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.usdcDai.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal(barBalanceDAIUSDC)
    })

    it("converts DAI/USDC using more complex path and JoeMakerV1 to make sure V3 converts as much as V1", async function () {
      this.joeMaker = await this.joeMakerCF.deploy(FACTORY_ADDRESS, BAR_ADDRESS, JOE_ADDRESS, WAVAX_ADDRESS)
      await this.joeMaker.deployed()

      await this.zap.zapIn(this.usdcDai.address, { value: "2000000000000000000" })
      await this.usdcDai.transfer(this.joeMaker.address, await this.usdcDai.balanceOf(this.dev.address))
      await this.joeMaker.setBridge(this.usdc.address, this.joe.address)
      await this.joeMaker.setBridge(this.dai.address, this.usdc.address)
      await this.joeMaker.convert(this.dai.address, this.usdc.address)
      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.usdcDai.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal(barBalanceDAIUSDC)
    })

    it("should convert reflect tokens TRACTOR/AVAX", async function () {
      const reserves = await this.tractorAvax.getReserves()
      const reserve0 = reserves["_reserve0"]
      const reserve1 = reserves["_reserve1"]

      // We swap 1 $AVAX for $TRACTOR, 2% cause of the reflect token and 0.3% Fees on swap.
      const amountOutWithFeesAndReflectFees = reserve0.mul(getBigNumber(1)).div(reserve1).mul("98").div("100").mul("997").div("1000")

      await this.router.swapAVAXForExactTokens(
        amountOutWithFeesAndReflectFees,
        [this.wavax.address, this.tractor.address],
        this.dev.address,
        "1111111111111111",
        { value: "1000000000000000000" }
      )

      // We get the exact balance.
      const balance = await this.tractor.balanceOf(this.dev.address)

      this.tractor.approve(this.router.address, "100000000000000000000000000")

      this.router.addLiquidityAVAX(this.tractor.address, balance, "0", "0", this.joeMakerV3.address, "11111111111111111", {
        value: "1000000000000000000",
      })

      await this.joeMakerV3.convert(this.tractor.address, this.wavax.address)

      expect(await this.joe.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.usdcDai.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("67845618054287432177393232")
    })

    it("reverts if it loops back", async function () {
      await this.zap.zapIn(this.usdcDai.address, { value: "2000000000000000000" })
      await this.usdcDai.transfer(this.joeMakerV3.address, await this.wbtcUsdc.balanceOf(this.dev.address))
      await this.joeMakerV3.setBridge(this.wbtc.address, this.usdc.address)
      await this.joeMakerV3.setBridge(this.usdc.address, this.wbtc.address)
      await expect(this.joeMakerV3.convert(this.dai.address, this.usdc.address)).to.be.reverted
    })

    it("reverts if caller is not EOA", async function () {
      const exploiterCF = await ethers.getContractFactory("JoeMakerExploitMock")
      const exploiter = await exploiterCF.deploy(this.joeMakerV3.address)
      await exploiter.deployed()

      await this.zap.zapIn(this.joeAvax.address, { value: "2000000000000000000" })
      await this.joeAvax.transfer(this.joeMakerV3.address, await this.wbtcUsdc.balanceOf(this.dev.address))
      await expect(exploiter.convert(this.joe.address, this.wavax.address)).to.be.revertedWith("JoeMakerV3: must use EOA")
    })

    it("reverts if pair does not exist", async function () {
      await expect(this.joeMakerV3.convert(this.joe.address, this.joeAvax.address)).to.be.revertedWith("JoeMakerV3: Invalid pair")
    })
  })

  describe("convertMultiple", function () {
    it("should allow to convert multiple", async function () {
      await this.zap.zapIn(this.daiAvax.address, { value: "2000000000000000000" })
      await this.zap.zapIn(this.joeAvax.address, { value: "2000000000000000000" })
      await this.daiAvax.transfer(this.joeMakerV3.address, await this.daiAvax.balanceOf(this.dev.address))
      await this.joeAvax.transfer(this.joeMakerV3.address, await this.joeAvax.balanceOf(this.dev.address))
      await this.joeMakerV3.convertMultiple([this.dai.address, this.joe.address], [this.wavax.address, this.wavax.address])
      expect(await this.joe.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.daiAvax.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("67845675227962521286137397")
    })
  })

  describe("devCut", function () {
    it("should redirect 50% of JOE to dev address", async function () {
      await this.joeMakerV3.setDevAddr(this.dev.address)
      await this.joeMakerV3.setDevCut("5000")

      this.wavaxERC20 = await this.ERC20CF.attach(WAVAX_ADDRESS)

      const barBalance = await this.joe.balanceOf(BAR_ADDRESS)
      const devBalance = await this.wavaxERC20.balanceOf(this.dev.address)

      await this.zap.zapIn(this.usdcAvax.address, { value: "2000000000000000000" })
      await this.usdcAvax.transfer(this.joeMakerV3.address, await this.usdcAvax.balanceOf(this.dev.address))
      await this.joeMakerV3.convert(this.usdc.address, this.wavax.address)
      expect(await this.joe.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect(await this.usdcAvax.balanceOf(this.joeMakerV3.address)).to.equal(0)
      expect((await this.joe.balanceOf(BAR_ADDRESS)) - barBalance).to.be.greaterThan(0)
      expect((await this.wavaxERC20.balanceOf(this.dev.address)) - devBalance).to.be.greaterThan(0)
    })
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
