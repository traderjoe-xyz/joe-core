// @ts-ignore
import { ethers, network, waffle } from "hardhat"
import { expect } from "chai"
import { BigNumber } from "ethers"
import { WAVAX } from "@traderjoe-xyz/sdk"

const JOE_ADDRESS = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd"
const WAVAX_ADDRESS = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7"
const USDT_ADDRESS = "0xc7198437980c041c805A1EDcbA50c1Ce5db95118"
const USDC_ADDRESS = "0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664"
const APEX_ADDRESS = "0xd039c9079ca7f2a87d632a9c0d7cea0137bacfb5"

const ROUTER_ADDRESS = "0x60aE616a2155Ee3d9A68541Ba4544862310933d4"

const JOEAVAX_ADDRESS = "0x454E67025631C065d3cFAD6d71E6892f74487a15"
const AVAXAPEX_ADDRESS = "0x824Ca83923990b91836ea927c14C1fb1B1790B08"
const USDCUSDT_ADDRESS = "0x2E02539203256c83c7a9F6fA6f8608A32A2b1Ca2"

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
    this.dev = this.signers[0]
    this.alice = this.signers[1]

    // Contracts
    this.router = await this.RouterCF.attach(ROUTER_ADDRESS, this.alice)

    // Tokens
    this.wavax = await ethers.getContractAt("IWAVAX", WAVAX_ADDRESS)
    this.wavax_erc20 = await this.ERC20CF.attach(WAVAX_ADDRESS)
    this.joe = await this.ERC20CF.attach(JOE_ADDRESS)
    this.usdt = await this.ERC20CF.attach(USDT_ADDRESS)
    this.usdc = await this.ERC20CF.attach(USDC_ADDRESS)
    this.apex = await this.ERC20CF.attach(APEX_ADDRESS)

    // Pairs
    this.joeAvax = await this.PairCF.attach(JOEAVAX_ADDRESS)
    this.usdcUsdt = await this.PairCF.attach(USDCUSDT_ADDRESS)
    this.avaxApex = await this.PairCF.attach(AVAXAPEX_ADDRESS)
  })

  beforeEach(async function () {
    // We reset the state before each tests
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: "https://api.avax.network/ext/bc/C/rpc",
            blockNumber: 8104212,
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

  describe("Revert", function () {
    it("Revert on zapInAVAX", async function () {
      //AVAX was at ~$83.05, so this will revert (as there is the 0.3 swap fees)
      await expect(
        this.zapV2
          .connect(this.alice)
          .zapInAVAX("0", ethers.utils.parseUnits("41.5", 6), [WAVAX_ADDRESS, USDT_ADDRESS, USDC_ADDRESS], [WAVAX_ADDRESS, USDC_ADDRESS, USDT_ADDRESS], {
            value: ethers.utils.parseEther("1"),
          })
      ).to.be.revertedWith("ZapV2: INSUFFICIENT_B_AMOUNT")
    })

    it("Revert on zapInTokens", async function () {
      //AVAX was at ~$83.05, so this will revert (as there is the 0.3 swap fees)
      await this.wavax.connect(this.alice).deposit({ value: ethers.utils.parseEther("1") })
      await this.wavax_erc20.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))
      await expect(
        this.zapV2
          .connect(this.alice)
          .zapInToken(
            this.wavax.address,
            ethers.utils.parseEther("1"),
            ethers.utils.parseUnits("41.5", 6),
            "0",
            [WAVAX_ADDRESS, USDT_ADDRESS, USDC_ADDRESS],
            [WAVAX_ADDRESS, USDC_ADDRESS, USDT_ADDRESS]
          )
      ).to.be.revertedWith("ZapV2: INSUFFICIENT_A_AMOUNT")
    })

    it("Revert on zapOutAVAX", async function () {
      await this.zapV2.connect(this.alice).zapInAVAX(0, 0, [WAVAX_ADDRESS, JOE_ADDRESS], [WAVAX_ADDRESS], { value: ethers.utils.parseEther("1") })
      expect(await this.joeAvax.balanceOf(this.alice.address)).to.equal("2690071399116878197")

      await this.joeAvax.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))
      // should receive 39598352614090637276 JOE, so we use this value + 1 to make sure it reverts
      await expect(
        this.zapV2
          .connect(this.alice)
          .zapOutToken(
            this.joeAvax.address,
            await this.joeAvax.balanceOf(this.alice.address),
            "39598352614090637277",
            [JOE_ADDRESS],
            [WAVAX_ADDRESS, JOE_ADDRESS]
          )
      ).to.be.revertedWith("ZapV2: INSUFFICIENT_TOKEN_AMOUNT")

      await this.zapV2
          .connect(this.alice)
          .zapOutToken(
              this.joeAvax.address,
              await this.joeAvax.balanceOf(this.alice.address),
              "39598352614090637276",
              [JOE_ADDRESS],
              [WAVAX_ADDRESS, JOE_ADDRESS]
          )
    })
  })

  describe("zapInAVAX", function () {
    it("zap 1 AVAX to JOE/WAVAX and zapOutAVAX to JOE", async function () {
      await this.zapV2.connect(this.alice).zapInAVAX(0, 0, [WAVAX_ADDRESS, JOE_ADDRESS], [WAVAX_ADDRESS], { value: ethers.utils.parseEther("1") })
      expect(await this.joeAvax.balanceOf(this.alice.address)).to.equal("2690071399116878197")

      await this.joeAvax.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))
      await this.zapV2
        .connect(this.alice)
        .zapOutToken(this.joeAvax.address, await this.joeAvax.balanceOf(this.alice.address), 0, [JOE_ADDRESS], [WAVAX_ADDRESS, JOE_ADDRESS])
      expect(await this.joe.balanceOf(this.alice.address)).to.equal("39598352614090637276")
    })

    it("zap 1 AVAX to USDC/USDT and zapOutAVAX to AVAX, testing the 2 paths inverted", async function () {
      const provider = waffle.provider
      await this.zapV2
        .connect(this.alice)
        .zapInAVAX(0, 0, [WAVAX_ADDRESS, USDT_ADDRESS, USDC_ADDRESS], [WAVAX_ADDRESS, USDC_ADDRESS, USDT_ADDRESS], { value: ethers.utils.parseEther("1") })
      await this.zapV2
        .connect(this.alice)
        .zapInAVAX(0, 0, [WAVAX_ADDRESS, USDC_ADDRESS, USDT_ADDRESS], [WAVAX_ADDRESS, USDT_ADDRESS, USDC_ADDRESS], { value: ethers.utils.parseEther("1") })
      const balanceBefore = await provider.getBalance(this.alice.address)
      expect(await this.usdcUsdt.balanceOf(this.alice.address)).to.equal("81500860")

      await this.usdcUsdt.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))
      await this.zapV2
        .connect(this.alice)
        .zapOutAVAX(
          this.usdcUsdt.address,
          (await this.usdcUsdt.balanceOf(this.alice.address)).div(2),
          0,
          [USDT_ADDRESS, USDC_ADDRESS, WAVAX_ADDRESS],
          [USDC_ADDRESS, USDT_ADDRESS, WAVAX_ADDRESS]
        )
      await this.zapV2
        .connect(this.alice)
        .zapOutAVAX(
          this.usdcUsdt.address,
          await this.usdcUsdt.balanceOf(this.alice.address),
          0,
          [USDC_ADDRESS, USDT_ADDRESS, WAVAX_ADDRESS],
          [USDT_ADDRESS, USDC_ADDRESS, WAVAX_ADDRESS]
        )
      expect(parseInt((await provider.getBalance(this.alice.address)).sub(balanceBefore).toString())).to.be.greaterThan(0)
    })

    it("zap JOE to APEX/AVAX and zapOutAVAX to USDT", async function () {
      await this.router
        .connect(this.alice)
        .swapExactAVAXForTokens("0", [WAVAX_ADDRESS, JOE_ADDRESS], this.alice.address, ethers.utils.parseEther("0.1"), { value: ethers.utils.parseEther("1") })
      const balance = await this.joe.balanceOf(this.alice.address)

      await this.joe.connect(this.alice).approve(this.zapV2.address, "10000000000000000000000000000")

      await this.zapV2
        .connect(this.alice)
        .zapInToken(JOE_ADDRESS, balance, 0, 0, [JOE_ADDRESS, WAVAX_ADDRESS, APEX_ADDRESS], [JOE_ADDRESS, WAVAX_ADDRESS])

      expect(await this.avaxApex.balanceOf(this.alice.address)).to.equal("139109741023754377")
      await this.avaxApex.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))

      await this.zapV2
        .connect(this.alice)
        .zapOutToken(
          this.avaxApex.address,
          await this.avaxApex.balanceOf(this.alice.address),
          0,
          [APEX_ADDRESS, WAVAX_ADDRESS, USDT_ADDRESS],
          [WAVAX_ADDRESS, USDT_ADDRESS]
        )
      expect(await this.usdt.balanceOf(this.alice.address)).to.equal("62711017")
    })

    it("zap APEX to APEX/AVAX and zapOutAVAX to APEX", async function () {
      await this.router
        .connect(this.alice)
        .swapExactAVAXForTokens("0", [WAVAX_ADDRESS, APEX_ADDRESS], this.alice.address, ethers.utils.parseEther("0.1"), { value: ethers.utils.parseEther("1") })
      const balance = await this.apex.balanceOf(this.alice.address)

      await this.apex.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))

      await this.zapV2.connect(this.alice).zapInToken(APEX_ADDRESS, balance, 0, 0, [APEX_ADDRESS], [APEX_ADDRESS, WAVAX_ADDRESS])

      expect(await this.avaxApex.balanceOf(this.alice.address)).to.equal("117716476044675464")

      await this.avaxApex.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))

      await this.zapV2
        .connect(this.alice)
        .zapOutToken(this.avaxApex.address, await this.avaxApex.balanceOf(this.alice.address), 0, [APEX_ADDRESS], [WAVAX_ADDRESS, APEX_ADDRESS])
      expect(await this.apex.balanceOf(this.alice.address)).to.equal("79339566748533517")
    })
  })

  // add tests for slippage, reverting if not enough etc

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
