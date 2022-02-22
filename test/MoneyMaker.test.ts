// @ts-ignore
import { ethers, network } from "hardhat"
import { expect } from "chai"
import { getBigNumber } from "./utilities"

const ROUTER_ADDRESS = "0x60aE616a2155Ee3d9A68541Ba4544862310933d4"

const WAVAX_ADDRESS = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7"
const JOE_ADDRESS = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd"
const USDT_ADDRESS = "0xc7198437980c041c805A1EDcbA50c1Ce5db95118"
const USDC_ADDRESS = "0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664"
const DAI_ADDRESS = "0xd586E7F844cEa2F87f50152665BCbc2C279D8d70"
const MIM_ADDRESS = "0x130966628846bfd36ff31a822705796e8cb8c18d"
const TIME_ADDRESS = "0xb54f16fb19478766a268f172c9480f8da1a7c9c3"
const WBTC_ADDRESS = "0x50b7545627a5162F82A992c33b87aDc75187B218"
const TRACTOR_ADDRESS = "0x542fA0B261503333B90fE60c78F2BeeD16b7b7fD"

const JOEAVAX_ADDRESS = "0x454E67025631C065d3cFAD6d71E6892f74487a15"
const USDCAVAX_ADDRESS = "0xa389f9430876455c36478deea9769b7ca4e3ddb1"
const MIMTIME_ADDRESS = "0x113f413371fc4cc4c9d6416cf1de9dfd7bf747df"
const MIMAVAX_ADDRESS = "0x781655d802670bba3c89aebaaea59d3182fd755d"
const TRACTORAVAX_ADDRESS = "0x601e0f63be88a52b79dbac667d6b4a167ce39113"
const USDCDAI_ADDRESS = "0x63ABE32d0Ee76C05a11838722A63e012008416E6"
const JOEUSDT_ADDRESS = "0x1643de2efB8e35374D796297a9f95f64C082a8ce"

const FACTORY_ADDRESS = "0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10"
const ZAP_ADDRESS = "0x2C7B8e971c704371772eDaf16e0dB381A8D02027"
const BAR_ADDRESS = "0x57319d41F71E81F3c65F2a47CA4e001EbAFd4F33"

const DEADLINE = "111111111111111111"

describe("moneyMaker", function () {
  before(async function () {
    // ABIs
    this.moneyMakerCF = await ethers.getContractFactory("MoneyMaker")
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
    this.wavaxERC20 = await this.ERC20CF.attach(WAVAX_ADDRESS)
    this.joe = await this.ERC20CF.attach(JOE_ADDRESS)
    this.usdc = await this.ERC20CF.attach(USDC_ADDRESS)
    this.usdt = await this.ERC20CF.attach(USDT_ADDRESS)
    this.dai = await this.ERC20CF.attach(DAI_ADDRESS)
    this.wbtc = await this.ERC20CF.attach(WBTC_ADDRESS)
    this.mim = await this.ERC20CF.attach(MIM_ADDRESS)
    this.time = await this.ERC20CF.attach(TIME_ADDRESS)
    this.tractor = await this.ERC20CF.attach(TRACTOR_ADDRESS)

    // Pairs
    this.joeAvax = await this.PairCF.attach(JOEAVAX_ADDRESS, this.dev)
    this.joeUsdt = await this.PairCF.attach(JOEUSDT_ADDRESS, this.dev)
    this.avaxUsdc = await this.PairCF.attach(USDCAVAX_ADDRESS, this.dev)
    this.usdcDai = await this.PairCF.attach(USDCDAI_ADDRESS, this.dev)
    this.mimTime = await this.PairCF.attach(MIMTIME_ADDRESS, this.dev)
    this.mimAvax = await this.PairCF.attach(MIMAVAX_ADDRESS, this.dev)
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
            blockNumber: 8465376,
          },
          live: false,
          saveDeployments: true,
          tags: ["test", "local"],
        },
      ],
    })

    // We redeploy moneyMaker for each tests too
    this.moneyMaker = await this.moneyMakerCF.deploy(FACTORY_ADDRESS, BAR_ADDRESS, USDC_ADDRESS, WAVAX_ADDRESS)
    await this.moneyMaker.deployed()
  })

  describe("setBridge", function () {
    it("does not allow to set bridge for Token", async function () {
      await expect(this.moneyMaker.setBridge(this.moneyMaker.tokenTo(), this.wavax.address)).to.be.revertedWith("MoneyMaker: Invalid bridge")
    })

    it("does not allow to set bridge for WAVAX", async function () {
      await expect(this.moneyMaker.setBridge(this.wavax.address, this.joe.address)).to.be.revertedWith("MoneyMaker: Invalid bridge")
    })

    it("does not allow to set bridge to itself", async function () {
      await expect(this.moneyMaker.setBridge(this.dai.address, this.dai.address)).to.be.revertedWith("MoneyMaker: Invalid bridge")
    })

    it("emits correct event on bridge", async function () {
      await expect(this.moneyMaker.setBridge(this.dai.address, this.joe.address))
        .to.emit(this.moneyMaker, "LogBridgeSet")
        .withArgs(this.dai.address, ethers.constants.AddressZero, this.joe.address)
    })
  })

  describe("convert Tokens", function () {
    it("should convert WAVAX", async function () {
      await this.wavax.deposit({ value: ethers.utils.parseEther("2") })
      await this.wavax.transfer(this.moneyMaker.address, await this.wavaxERC20.balanceOf(this.dev.address))
      await this.moneyMaker.convert(this.wavax.address, this.wavax.address, "100")
      expect(await this.usdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.wavaxERC20.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("215434297")
    })

    it("should convert USDC", async function () {
      await this.router.swapExactAVAXForTokens("0", [this.wavax.address, this.usdc.address], this.moneyMaker.address, DEADLINE, {
        value: ethers.utils.parseEther("2"),
      })
      await this.moneyMaker.convert(this.usdc.address, this.usdc.address, "100")
      expect(await this.usdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.wavaxERC20.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("215434297")
    })

    it("should convert WBTC", async function () {
      await this.router.swapExactAVAXForTokens("0", [this.wavax.address, this.wbtc.address], this.moneyMaker.address, DEADLINE, {
        value: ethers.utils.parseEther("2"),
      })
      await this.moneyMaker.convert(this.wbtc.address, this.wbtc.address, "100")
      expect(await this.usdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.wavaxERC20.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("214143468")
    })
  })

  describe("convert Pairs", function () {
    it("should convert AVAX - USDC", async function () {
      await this.zap.zapIn(this.avaxUsdc.address, { value: ethers.utils.parseEther("2") })
      await this.avaxUsdc.transfer(this.moneyMaker.address, await this.avaxUsdc.balanceOf(this.dev.address))
      await this.moneyMaker.convert(this.usdc.address, this.wavax.address, "100")
      expect(await this.usdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.avaxUsdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("215111242")
    })

    it("should convert USDC - DAI", async function () {
      await this.zap.zapIn(this.usdcDai.address, { value: ethers.utils.parseEther("2") })
      await this.usdcDai.transfer(this.moneyMaker.address, await this.usdcDai.balanceOf(this.dev.address))
      await this.moneyMaker.convert(this.dai.address, this.usdc.address, "100")
      expect(await this.usdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.usdcDai.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("214878919")
    })

    it("Should convert JOE - AVAX above slippage", async function () {
      await this.zap.zapIn(this.joeAvax.address, { value: "2000000000000000000" })

      const joeAvax = await getPairInfo(this.joeAvax, this.dev.address)
      const avaxUsdc = await getPairInfo(this.avaxUsdc, this.dev.address)

      const [joeAmount, avaxAmount] =
        this.joe.address == joeAvax.token0 ? [joeAvax.amount0, joeAvax.amount1] : [joeAvax.amount1, joeAvax.amount0]

      const swappedJoeToAvax = swapTo(joeAvax, (await joeAvax.token0) == this.joe.address, joeAmount, "9900")
      const swappedAvaxToUsdc = swapTo(avaxUsdc, (await avaxUsdc.token0) == this.wavax.address, avaxAmount.add(swappedJoeToAvax), "9900")

      await this.joeAvax.transfer(this.moneyMaker.address, await this.joeAvax.balanceOf(this.dev.address))
      await this.moneyMaker.convert(this.joe.address, this.wavax.address, "100")

      expect(await this.usdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.joeAvax.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect((await this.usdc.balanceOf(BAR_ADDRESS)).sub(swappedAvaxToUsdc).toNumber()).to.be.above(0)
    })

    it("should convert MIM - TIME above slippage", async function () {
      await this.zap.zapIn(this.mimTime.address, { value: ethers.utils.parseEther("2") })
      await this.mimTime.transfer(this.moneyMaker.address, await this.mimTime.balanceOf(this.dev.address))
      await this.moneyMaker.setBridge(this.time.address, this.mim.address)
      await this.moneyMaker.setBridge(this.mim.address, this.wavax.address)

      const mimTime = await getPairInfo(this.mimTime, this.dev.address)
      const mimAvax = await getPairInfo(this.mimAvax, this.dev.address)
      const avaxUsdc = await getPairInfo(this.avaxUsdc, this.dev.address)

      const [mimAmount, timeAmount] =
        this.mim.address == mimTime.token0 ? [mimTime.amount0, mimTime.amount1] : [mimTime.amount1, mimTime.amount0]

      const swappedTimeToMim = swapTo(mimTime, (await mimTime.token0) == this.time.address, timeAmount, "9900")
      const swappedMimToAvax = swapTo(mimAvax, (await mimAvax.token0) == this.mim.address, mimAmount.add(swappedTimeToMim), "9900")
      const swappedAvaxToUsdc = swapTo(avaxUsdc, (await avaxUsdc.token0) == this.wavax.address, swappedMimToAvax, "9900")

      await this.moneyMaker.convert(this.mim.address, this.time.address, "100")
      expect(await this.usdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.mimTime.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect((await this.usdc.balanceOf(BAR_ADDRESS)).sub(swappedAvaxToUsdc).toNumber()).to.be.above(0)
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
        DEADLINE,
        { value: ethers.utils.parseEther("1") }
      )

      // We get the exact balance.
      const balance = await this.tractor.balanceOf(this.dev.address)

      this.tractor.approve(this.router.address, ethers.utils.parseEther("100000000"))

      this.router.addLiquidityAVAX(this.tractor.address, balance, "0", "0", this.moneyMaker.address, DEADLINE, {
        value: ethers.utils.parseEther("1"),
      })

      await this.moneyMaker.convert(this.tractor.address, this.wavax.address, "100")

      expect(await this.usdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.usdcDai.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("186168809")
    })

    it("reverts if slippage is lower than 0.3% (fees for swap)", async function () {
      await this.zap.zapIn(this.joeAvax.address, { value: "2000000000000000000" })
      await this.joeAvax.transfer(this.moneyMaker.address, await this.joeAvax.balanceOf(this.dev.address))
      await expect(this.moneyMaker.convert(this.joe.address, this.wavax.address, "29")).to.be.revertedWith("MoneyMaker: Slippage caught") // slippage at 0.29% this will revert as the fee for a swap is 0.3%
    })

    it("reverts if using a pair with really low liquidity even with slippage at maximum", async function () {
      await this.zap.zapIn(this.mimTime.address, { value: "2000000000000000000" })
      await this.mimTime.transfer(this.moneyMaker.address, await this.mimTime.balanceOf(this.dev.address))
      await this.moneyMaker.setBridge(this.mim.address, this.joe.address)
      await expect(this.moneyMaker.convert(this.mim.address, this.time.address, "4999")).to.be.revertedWith("MoneyMaker: Slippage caught") // slippage at 1% this will revert as the JOE/MIM pair has really low liquidity.
    })

    it("reverts if convert is called by non-authorised user", async function () {
      await this.zap.zapIn(this.avaxUsdc.address, { value: ethers.utils.parseEther("2") })
      await this.avaxUsdc.transfer(this.moneyMaker.address, await this.avaxUsdc.balanceOf(this.dev.address))
      await expect(this.moneyMaker.connect(this.alice).convert(this.usdc.address, this.wavax.address, "100")).to.be.revertedWith(
        "MoneyMaker: FORBIDDEN"
      )
    })

    it("reverts if it loops back", async function () {
      await this.zap.zapIn(this.joeUsdt.address, { value: ethers.utils.parseEther("2") })
      await this.joeUsdt.transfer(this.moneyMaker.address, await this.joeUsdt.balanceOf(this.dev.address))
      await this.moneyMaker.setBridge(this.joe.address, this.usdt.address)
      await this.moneyMaker.setBridge(this.usdt.address, this.joe.address)
      await expect(this.moneyMaker.convert(this.usdt.address, this.joe.address, "100")).to.be.reverted
    })

    it("reverts if pair does not exist", async function () {
      await expect(this.moneyMaker.convert(this.usdc.address, this.avaxUsdc.address, "100")).to.be.revertedWith("MoneyMaker: Invalid pair")
    })
  })

  describe("convertMultiple", function () {
    it("should allow to convert multiple", async function () {
      await this.zap.zapIn(this.joeAvax.address, { value: ethers.utils.parseEther("2") })
      await this.zap.zapIn(this.avaxUsdc.address, { value: ethers.utils.parseEther("2") })
      await this.joeAvax.transfer(this.moneyMaker.address, await this.joeAvax.balanceOf(this.dev.address))
      await this.avaxUsdc.transfer(this.moneyMaker.address, await this.avaxUsdc.balanceOf(this.dev.address))
      await this.moneyMaker.convertMultiple([this.joe.address, this.usdc.address], [this.wavax.address, this.wavax.address], "100")
      expect(await this.usdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.joeAvax.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.avaxUsdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("429576577")
    })
  })

  describe("devCut", function () {
    it("should redirect 50% of JOE to dev address", async function () {
      await this.moneyMaker.setDevAddr(this.dev.address)
      await this.moneyMaker.setDevCut("5000")

      this.wavaxERC20 = await this.ERC20CF.attach(WAVAX_ADDRESS)

      const barBalance = await this.usdc.balanceOf(BAR_ADDRESS)
      const devBalance = await this.wavaxERC20.balanceOf(this.dev.address)

      await this.zap.zapIn(this.avaxUsdc.address, { value: ethers.utils.parseEther("2") })
      await this.avaxUsdc.transfer(this.moneyMaker.address, await this.avaxUsdc.balanceOf(this.dev.address))
      await this.moneyMaker.convert(this.usdc.address, this.wavax.address, "100")
      expect(await this.usdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect(await this.avaxUsdc.balanceOf(this.moneyMaker.address)).to.equal(0)
      expect((await this.usdc.balanceOf(BAR_ADDRESS)) - barBalance).to.be.above(0)
      expect((await this.wavaxERC20.balanceOf(this.dev.address)) - devBalance).to.be.above(0)
    })
  })

  describe("setToken", function () {
    it("should convert JOE - AVAX to JOE", async function () {
      this.moneyMaker.setTokenToAddress(this.joe.address)

      this.joeMaker = await this.joeMakerCF.deploy(FACTORY_ADDRESS, BAR_ADDRESS, JOE_ADDRESS, WAVAX_ADDRESS)
      await this.joeMaker.deployed()

      let previousBalance = await this.joe.balanceOf(BAR_ADDRESS)
      await this.zap.zapIn(this.avaxUsdc.address, { value: ethers.utils.parseEther("2") })
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal(previousBalance)

      await this.avaxUsdc.transfer(this.joeMaker.address, (await this.avaxUsdc.balanceOf(this.dev.address)).div(2))
      await this.joeMaker.convert(this.usdc.address, this.wavax.address)
      expect((await this.joe.balanceOf(BAR_ADDRESS)).sub(previousBalance.add(ethers.utils.parseEther("50")))).to.be.above(0)

      previousBalance = await this.joe.balanceOf(BAR_ADDRESS)
      await this.avaxUsdc.transfer(this.moneyMaker.address, await this.avaxUsdc.balanceOf(this.dev.address))
      await this.moneyMaker.convert(this.usdc.address, this.wavax.address, "100")
      expect((await this.joe.balanceOf(BAR_ADDRESS)).sub(previousBalance.add(ethers.utils.parseEther("50")))).to.be.above(0)

      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.avaxUsdc.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.avaxUsdc.balanceOf(this.moneyMaker.address)).to.equal(0)
    })
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})

const getPairInfo = async (pair, dev) => {
  const reserves = await pair.getReserves()
  let reserve0 = reserves[0]
  let reserve1 = reserves[1]
  const totalSupply = await pair.totalSupply()
  const balanceSupply = await pair.balanceOf(dev)
  const amount0 = reserve0.mul(balanceSupply).div(totalSupply)
  const amount1 = reserve1.mul(balanceSupply).div(totalSupply)
  reserve0 = reserve0.sub(amount0)
  reserve1 = reserve1.sub(amount1)
  const token0 = await pair.token0()

  return {
    reserve0: reserve0,
    reserve1: reserve1,
    amount0: amount0,
    amount1: amount1,
    token0: token0,
  }
}

// rest is 10_000 - slippage
const swapTo = (pair, tokenIsToken0, amountIn, rest) => {
  const amountInWithSlippage = amountIn.mul(rest)
  const reserveIn = tokenIsToken0 ? pair.reserve0 : pair.reserve1
  const reserveOut = tokenIsToken0 ? pair.reserve1 : pair.reserve0
  return amountInWithSlippage.mul(reserveOut).div(reserveIn.mul("10000").add(amountInWithSlippage))
}
