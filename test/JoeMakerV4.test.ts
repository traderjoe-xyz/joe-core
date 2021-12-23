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
const TRACTORAVAX_ADDRESS = "0x601e0f63be88a52b79dbac667d6b4a167ce39113"
const USDCDAI_ADDRESS = "0x63ABE32d0Ee76C05a11838722A63e012008416E6"
const JOEUSDT_ADDRESS = "0x1643de2efB8e35374D796297a9f95f64C082a8ce"

const FACTORY_ADDRESS = "0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10"
const ZAP_ADDRESS = "0x2C7B8e971c704371772eDaf16e0dB381A8D02027"
const BAR_ADDRESS = "0x57319d41F71E81F3c65F2a47CA4e001EbAFd4F33"

describe("joeMakerV4", function () {
  before(async function () {
    // ABIs
    this.joeMakerV4CF = await ethers.getContractFactory("JoeMakerV4")
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

    // We redeploy joeMakerV4 for each tests too
    this.joeMakerV4 = await this.joeMakerV4CF.deploy(FACTORY_ADDRESS, BAR_ADDRESS, USDC_ADDRESS, WAVAX_ADDRESS)
    await this.joeMakerV4.deployed()
  })

  describe("setBridge", function () {
    it("does not allow to set bridge for Token", async function () {
      await expect(this.joeMakerV4.setBridge(this.joeMakerV4.tokenTo(), this.wavax.address)).to.be.revertedWith("JoeMakerV4: Invalid bridge")
    })

    it("does not allow to set bridge for WAVAX", async function () {
      await expect(this.joeMakerV4.setBridge(this.wavax.address, this.joe.address)).to.be.revertedWith("JoeMakerV4: Invalid bridge")
    })

    it("does not allow to set bridge to itself", async function () {
      await expect(this.joeMakerV4.setBridge(this.dai.address, this.dai.address)).to.be.revertedWith("JoeMakerV4: Invalid bridge")
    })

    it("emits correct event on bridge", async function () {
      await expect(this.joeMakerV4.setBridge(this.dai.address, this.joe.address))
        .to.emit(this.joeMakerV4, "LogBridgeSet")
        .withArgs(this.dai.address, this.joe.address)
    })
  })

  describe("convert Tokens", function () {
    it("should convert WAVAX", async function () {
      await this.wavax.deposit({ value: "2000000000000000000" })
      await this.wavax.transfer(this.joeMakerV4.address, await this.wavaxERC20.balanceOf(this.dev.address))
      await this.joeMakerV4.convert(this.wavax.address, this.wavax.address, "100")
      expect(await this.usdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.wavaxERC20.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("215434297")
    })

    it("should convert USDC", async function () {
      await this.router.swapExactAVAXForTokens("0", [this.wavax.address, this.usdc.address], this.joeMakerV4.address, "111111111111111111", {
        value: "2000000000000000000",
      })
      await this.joeMakerV4.convert(this.usdc.address, this.usdc.address, "100")
      expect(await this.usdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.wavaxERC20.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("215434297")
    })

    it("should convert WBTC", async function () {
      await this.router.swapExactAVAXForTokens("0", [this.wavax.address, this.wbtc.address], this.joeMakerV4.address, "111111111111111111", {
        value: "2000000000000000000",
      })
      await this.joeMakerV4.convert(this.wbtc.address, this.wbtc.address, "100")
      expect(await this.usdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.wavaxERC20.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("214143468")
    })
  })

  describe("convert Pairs", function () {
    it("should convert AVAX - USDC", async function () {
      await this.zap.zapIn(this.avaxUsdc.address, { value: "2000000000000000000" })
      await this.avaxUsdc.transfer(this.joeMakerV4.address, await this.avaxUsdc.balanceOf(this.dev.address))
      await this.joeMakerV4.convert(this.usdc.address, this.wavax.address, "100")
      expect(await this.usdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.avaxUsdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("215111242")
    })

    it("should convert USDC - DAI", async function () {
      await this.zap.zapIn(this.usdcDai.address, { value: "2000000000000000000" })
      await this.usdcDai.transfer(this.joeMakerV4.address, await this.usdcDai.balanceOf(this.dev.address))
      await this.joeMakerV4.convert(this.dai.address, this.usdc.address, "100")
      expect(await this.usdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.usdcDai.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("214878919")
    })

    it("should convert JOE - AVAX", async function () {
      await this.zap.zapIn(this.joeAvax.address, { value: "2000000000000000000" })
      await this.joeAvax.transfer(this.joeMakerV4.address, await this.joeAvax.balanceOf(this.dev.address))
      await this.joeMakerV4.convert(this.joe.address, this.wavax.address, "100")
      expect(await this.usdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.joeAvax.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("214466109")
    })

    it("should convert MIM - TIME", async function () {
      await this.zap.zapIn(this.mimTime.address, { value: "2000000000000000000" })
      await this.mimTime.transfer(this.joeMakerV4.address, await this.mimTime.balanceOf(this.dev.address))
      await this.joeMakerV4.setBridge(this.time.address, this.mim.address)
      await this.joeMakerV4.setBridge(this.mim.address, this.wavax.address)
      await this.joeMakerV4.convert(this.mim.address, this.time.address, "100")
      expect(await this.usdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.mimTime.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("213737823")
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

      this.router.addLiquidityAVAX(this.tractor.address, balance, "0", "0", this.joeMakerV4.address, "11111111111111111", {
        value: "1000000000000000000",
      })

      await this.joeMakerV4.convert(this.tractor.address, this.wavax.address, "100")

      expect(await this.usdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.usdcDai.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("186168809")
    })

    it("reverts if slippage is lower than 0.3% (fees for swap)", async function () {
      await this.zap.zapIn(this.joeAvax.address, { value: "2000000000000000000" })
      await this.joeAvax.transfer(this.joeMakerV4.address, await this.joeAvax.balanceOf(this.dev.address))
      await expect(this.joeMakerV4.convert(this.joe.address, this.wavax.address, "29"))
          .to.be.revertedWith("JoeMakerV4: Slippage caught") // slippage at 0.29% this will revert as the fee for a swap is 0.3%
    })

    it("reverts if using a pair with really low liquidity even with slippage at maximum", async function () {
      await this.zap.zapIn(this.mimTime.address, { value: "2000000000000000000" })
      await this.mimTime.transfer(this.joeMakerV4.address, await this.mimTime.balanceOf(this.dev.address))
      await this.joeMakerV4.setBridge(this.mim.address, this.joe.address)
      await expect(this.joeMakerV4.convert(this.mim.address, this.time.address, "4999"))
          .to.be.revertedWith("JoeMakerV4: Slippage caught") // slippage at 1% this will revert as the JOE/MIM pair has really low liquidity.
    })

    it("reverts if convert is called by non auth", async function () {
      await this.zap.zapIn(this.avaxUsdc.address, { value: "2000000000000000000" })
      await this.avaxUsdc.transfer(this.joeMakerV4.address, await this.avaxUsdc.balanceOf(this.dev.address))
      await expect(this.joeMakerV4.connect(this.alice).convert(this.usdc.address, this.wavax.address, "100")).to.be.revertedWith(
        "JoeMakerV4: FORBIDDEN"
      )
    })

    it("reverts if it loops back", async function () {
      await this.zap.zapIn(this.joeUsdt.address, { value: "2000000000000000000" })
      await this.joeUsdt.transfer(this.joeMakerV4.address, await this.joeUsdt.balanceOf(this.dev.address))
      await this.joeMakerV4.setBridge(this.joe.address, this.usdt.address)
      await this.joeMakerV4.setBridge(this.usdt.address, this.joe.address)
      await expect(this.joeMakerV4.convert(this.usdt.address, this.joe.address, "100")).to.be.reverted
    })

    it("reverts if pair does not exist", async function () {
      await expect(this.joeMakerV4.convert(this.usdc.address, this.avaxUsdc.address, "100")).to.be.revertedWith("JoeMakerV4: Invalid pair")
    })
  })

  describe("convertMultiple", function () {
    it("should allow to convert multiple", async function () {
      await this.zap.zapIn(this.joeAvax.address, { value: "2000000000000000000" })
      await this.zap.zapIn(this.avaxUsdc.address, { value: "2000000000000000000" })
      await this.joeAvax.transfer(this.joeMakerV4.address, await this.joeAvax.balanceOf(this.dev.address))
      await this.avaxUsdc.transfer(this.joeMakerV4.address, await this.avaxUsdc.balanceOf(this.dev.address))
      await this.joeMakerV4.convertMultiple([this.joe.address, this.usdc.address], [this.wavax.address, this.wavax.address], "100")
      expect(await this.usdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.joeAvax.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.avaxUsdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.usdc.balanceOf(BAR_ADDRESS)).to.equal("429576577")
    })
  })

  describe("devCut", function () {
    it("should redirect 50% of JOE to dev address", async function () {
      await this.joeMakerV4.setDevAddr(this.dev.address)
      await this.joeMakerV4.setDevCut("5000")

      this.wavaxERC20 = await this.ERC20CF.attach(WAVAX_ADDRESS)

      const barBalance = await this.usdc.balanceOf(BAR_ADDRESS)
      const devBalance = await this.wavaxERC20.balanceOf(this.dev.address)

      await this.zap.zapIn(this.avaxUsdc.address, { value: "2000000000000000000" })
      await this.avaxUsdc.transfer(this.joeMakerV4.address, await this.avaxUsdc.balanceOf(this.dev.address))
      await this.joeMakerV4.convert(this.usdc.address, this.wavax.address, "100")
      expect(await this.usdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect(await this.avaxUsdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
      expect((await this.usdc.balanceOf(BAR_ADDRESS)) - barBalance).to.be.greaterThan(0)
      expect((await this.wavaxERC20.balanceOf(this.dev.address)) - devBalance).to.be.greaterThan(0)
    })
  })

  describe("setToken", function () {
    it("should convert JOE - AVAX to JOE", async function () {
      this.joeMakerV4.setTokenToAddress(this.joe.address)

      this.joeMaker = await this.joeMakerCF.deploy(FACTORY_ADDRESS, BAR_ADDRESS, JOE_ADDRESS, WAVAX_ADDRESS)
      await this.joeMaker.deployed()

      await this.zap.zapIn(this.avaxUsdc.address, { value: "2000000000000000000" })
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("90009110009102767321753512")

      await this.avaxUsdc.transfer(this.joeMaker.address, (await this.avaxUsdc.balanceOf(this.dev.address)).div(2))
      await this.joeMaker.convert(this.usdc.address, this.wavax.address)
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("90009160457674355334497135")

      await this.avaxUsdc.transfer(this.joeMakerV4.address, await this.avaxUsdc.balanceOf(this.dev.address))
      await this.joeMakerV4.convert(this.usdc.address, this.wavax.address, "100")
      expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("90009210905950105791950559")

      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.avaxUsdc.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.avaxUsdc.balanceOf(this.joeMakerV4.address)).to.equal(0)
    })
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
