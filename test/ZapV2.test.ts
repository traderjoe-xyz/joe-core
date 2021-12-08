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

describe("zapV2", function () {
  before(async function () {
    // ABIs
    this.zapV2CF = await ethers.getContractFactory("ZapV2")
    this.joeMakerCF = await ethers.getContractFactory("JoeMaker")
    this.ERC20CF = await ethers.getContractFactory("JoeERC20")
    this.PairCF = await ethers.getContractFactory("JoePair")
    this.RouterCF = await ethers.getContractFactory("JoeRouter02")

    // Account
    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]

    // Contracts
    this.router = await this.RouterCF.attach(ROUTER_ADDRESS, this.alice)

    // Tokens
    this.wavax = await ethers.getContractAt("IWAVAX", WAVAX_ADDRESS, this.alice)
    this.joe = await this.ERC20CF.attach(JOE_ADDRESS)
    this.usdt = await this.ERC20CF.attach(USDT_ADDRESS)
    this.usdc = await this.ERC20CF.attach(USDC_ADDRESS)
    this.dai = await this.ERC20CF.attach(DAI_ADDRESS)
    this.link = await this.ERC20CF.attach(LINK_ADDRESS)
    this.wbtc = await this.ERC20CF.attach(WBTC_ADDRESS)
    this.tractor = await this.ERC20CF.attach(TRACTOR_ADDRESS)

    // Pairs
    this.joeAvax = await this.PairCF.attach(JOEAVAX_ADDRESS, this.alice)
    this.linkAvax = await this.PairCF.attach(LINKAVAX_ADDRESS, this.alice)
    this.daiAvax = await this.PairCF.attach(DAIAVAX_ADDRESS, this.alice)
    this.usdcAvax = await this.PairCF.attach(USDCAVAX_ADDRESS, this.alice)
    this.linkUsdc = await this.PairCF.attach(LINKUSDC_ADDRESS, this.alice)
    this.joeUsdt = await this.PairCF.attach(JOEUSDT_ADDRESS, this.alice)
    this.usdcDai = await this.PairCF.attach(USDCDAI_ADDRESS, this.alice)
    this.wbtcUsdc = await this.PairCF.attach(WBTCUSDC_ADDRESS, this.alice)
    this.tractorAvax = await this.PairCF.attach(TRACTORAVAX_ADDRESS, this.alice)
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

    // We redeploy zapV2 for each tests too
    this.zapV2 = await this.zapV2CF.deploy(ROUTER_ADDRESS)
    await this.zapV2.deployed()
  })

  describe("setBridge", function () {
    it("test", async function () {
      console.log(await this.zapV2.WAVAX())
    })
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
