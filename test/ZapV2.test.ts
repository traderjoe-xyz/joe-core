// @ts-ignore
import { ethers, network, waffle } from "hardhat"
import { expect } from "chai"
import { BigNumber } from "ethers"
import { WAVAX } from "@traderjoe-xyz/sdk"

const JOE_ADDRESS = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd"
const WAVAX_ADDRESS = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7"
const USDCE_ADDRESS = "0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664"
const USDC_ADDRESS = "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E"
const APEX_ADDRESS = "0xd039c9079ca7f2a87d632a9c0d7cea0137bacfb5"

const ROUTER_ADDRESS = "0x60aE616a2155Ee3d9A68541Ba4544862310933d4"

const JOEAVAX_ADDRESS = "0x454E67025631C065d3cFAD6d71E6892f74487a15"
const AVAXAPEX_ADDRESS = "0x824Ca83923990b91836ea927c14C1fb1B1790B08"
const USDCUSDCE_ADDRESS = "0x2A8A315e82F85D1f0658C5D66A452Bbdd9356783"
const AVAXUSDCE_ADDRESS = "0xeD8CBD9F0cE3C6986b22002F03c6475CEb7a6256"
const AVAXUSDC_ADDRESS = "0xf4003F4efBE8691B60249E6afbD307aBE7758adb"

const amountIn = ethers.utils.parseEther("1")

describe("ZapV2", function () {
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
    this.USDCE = await this.ERC20CF.attach(USDCE_ADDRESS)
    this.usdc = await this.ERC20CF.attach(USDC_ADDRESS)
    this.apex = await this.ERC20CF.attach(APEX_ADDRESS)

    // Pairs
    this.joeAvax = await this.PairCF.attach(JOEAVAX_ADDRESS)
    this.usdcUsdce = await this.PairCF.attach(USDCUSDCE_ADDRESS)
    this.avaxApex = await this.PairCF.attach(AVAXAPEX_ADDRESS)
    this.avaxUSDCE = await this.PairCF.attach(AVAXUSDCE_ADDRESS)
    this.avaxUsdc = await this.PairCF.attach(AVAXUSDC_ADDRESS)
  })

  beforeEach(async function () {
    // We reset the state before each tests
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: "https://api.avax.network/ext/bc/C/rpc",
          },
          live: false,
          saveDeployments: true,
          tags: ["test", "local"],
        },
      ],
    })

    // We redeploy zapV2 for each tests too
    this.zapV2 = await this.zapV2CF.deploy(WAVAX_ADDRESS, ROUTER_ADDRESS)
    await this.zapV2.deployed()
  })

  describe("Revert", function () {
    it("Revert on zapInAVAX", async function () {
      let amountOut = await getAmountOut(USDC_ADDRESS, this.avaxUsdc)
      await expect(
        this.zapV2.connect(this.alice).zapInAVAX(amountOut, 0, [WAVAX_ADDRESS, USDC_ADDRESS], [WAVAX_ADDRESS, USDCE_ADDRESS], {
          value: amountIn,
        })
      ).to.be.revertedWith("ZapV2: insufficient swapped amounts")
      amountOut = getAmountOut(USDCE_ADDRESS, this.avaxUSDCE)
      await expect(
        this.zapV2.connect(this.alice).zapInAVAX(0, amountOut, [WAVAX_ADDRESS, USDC_ADDRESS], [WAVAX_ADDRESS, USDCE_ADDRESS], {
          value: amountIn,
        })
      ).to.be.revertedWith("ZapV2: insufficient swapped amounts")
    })

    it("Revert on zapInTokens", async function () {
      await this.wavax.connect(this.alice).deposit({ value: ethers.utils.parseEther("1") })
      await this.wavax_erc20.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))
      let amountOut = await getAmountOut(USDCE_ADDRESS, this.avaxUSDCE)
      await expect(
        this.zapV2.connect(this.alice).zapInToken(amountIn, amountOut, 0, [WAVAX_ADDRESS, USDCE_ADDRESS], [WAVAX_ADDRESS, USDC_ADDRESS])
      ).to.be.revertedWith("ZapV2: insufficient swapped amounts")
      amountOut = getAmountOut(USDC_ADDRESS, this.avaxUsdc)
      await expect(
        this.zapV2.connect(this.alice).zapInToken(amountIn, 0, amountOut, [WAVAX_ADDRESS, USDCE_ADDRESS], [WAVAX_ADDRESS, USDC_ADDRESS])
      ).to.be.revertedWith("ZapV2: insufficient swapped amounts")
    })

    it("Revert on zapOutAVAX", async function () {
      await this.zapV2
        .connect(this.alice)
        .zapInAVAX(0, 0, [WAVAX_ADDRESS, JOE_ADDRESS], [WAVAX_ADDRESS], { value: ethers.utils.parseEther("1") })
      let amountOut = await getAmountOut(WAVAX_ADDRESS, this.joeAvax)
      await this.joeAvax.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))
      await expect(
        this.zapV2
          .connect(this.alice)
          .zapOutToken(await this.joeAvax.balanceOf(this.alice.address), amountOut, [JOE_ADDRESS], [WAVAX_ADDRESS, JOE_ADDRESS])
      ).to.be.revertedWith("ZapV2: insufficient swapped amounts")
      await expect(
        this.zapV2
          .connect(this.alice)
          .zapOutAVAX(await this.joeAvax.balanceOf(this.alice.address), amountOut, [JOE_ADDRESS, WAVAX_ADDRESS], [WAVAX_ADDRESS])
      ).to.be.revertedWith("ZapV2: insufficient swapped amounts")
    })

    it("Revert if an user tries to use withdraw", async function () {
      await expect(this.zapV2.connect(this.alice).withdraw(this.USDCE.address)).to.be.revertedWith("Ownable: caller is not the owner")
    })
  })

  describe("zapInAVAX", function () {
    it("zap 1 AVAX to JOE/WAVAX and zapOutAVAX to JOE", async function () {
      await this.zapV2
        .connect(this.alice)
        .zapInAVAX(0, 0, [WAVAX_ADDRESS, JOE_ADDRESS], [WAVAX_ADDRESS], { value: ethers.utils.parseEther("1") })
      expect(await this.joeAvax.balanceOf(this.alice.address))

      await this.joeAvax.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))
      let amountOut = await getAmountOut(WAVAX_ADDRESS, this.joeAvax)

      await this.zapV2
        .connect(this.alice)
        .zapOutToken(await this.joeAvax.balanceOf(this.alice.address), amountOut.mul(995).div(1000), [JOE_ADDRESS], [WAVAX_ADDRESS, JOE_ADDRESS])
    })

    it("zap 1 AVAX to USDC/USDCE and zapOutAVAX to AVAX, testing the 2 paths inverted", async function () {
      const provider = waffle.provider
      await this.zapV2
        .connect(this.alice)
        .zapInAVAX(0, 0, [WAVAX_ADDRESS, USDCE_ADDRESS, USDC_ADDRESS], [WAVAX_ADDRESS, USDC_ADDRESS, USDCE_ADDRESS], {
          value: ethers.utils.parseEther("1"),
        })

      await this.zapV2
        .connect(this.alice)
        .zapInAVAX(0, 0, [WAVAX_ADDRESS, USDC_ADDRESS, USDCE_ADDRESS], [WAVAX_ADDRESS, USDCE_ADDRESS, USDC_ADDRESS], {
          value: ethers.utils.parseEther("1"),
        })

      const balanceBefore = await provider.getBalance(this.alice.address)

      expect(await this.usdcUsdce.balanceOf(this.alice.address)).to.be.above("0")

      await this.usdcUsdce.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))
      await this.zapV2
        .connect(this.alice)
        .zapOutAVAX(
          (await this.usdcUsdce.balanceOf(this.alice.address)).div(2),
          0,
          [USDCE_ADDRESS, USDC_ADDRESS, WAVAX_ADDRESS],
          [USDC_ADDRESS, USDCE_ADDRESS, WAVAX_ADDRESS]
        )
      await this.zapV2
        .connect(this.alice)
        .zapOutAVAX(
          await this.usdcUsdce.balanceOf(this.alice.address),
          0,
          [USDC_ADDRESS, USDCE_ADDRESS, WAVAX_ADDRESS],
          [USDCE_ADDRESS, USDC_ADDRESS, WAVAX_ADDRESS]
        )
      expect(await provider.getBalance(this.alice.address)).to.be.above(balanceBefore)
    })

    it("zap JOE to APEX/AVAX and zapOutAVAX to USDCE", async function () {
      await this.router
        .connect(this.alice)
        .swapExactAVAXForTokens("0", [WAVAX_ADDRESS, JOE_ADDRESS], this.alice.address, ethers.utils.parseEther("0.1"), {
          value: ethers.utils.parseEther("1"),
        })
      const balance = await this.joe.balanceOf(this.alice.address)

      await this.joe.connect(this.alice).approve(this.zapV2.address, "10000000000000000000000000000")

      await this.zapV2.connect(this.alice).zapInToken(balance, 0, 0, [JOE_ADDRESS, WAVAX_ADDRESS, APEX_ADDRESS], [JOE_ADDRESS, WAVAX_ADDRESS])

      expect(await this.avaxApex.balanceOf(this.alice.address)).to.be.above(0)
      await this.avaxApex.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))

      await this.zapV2
        .connect(this.alice)
        .zapOutToken(
          await this.avaxApex.balanceOf(this.alice.address),
          0,
          [APEX_ADDRESS, WAVAX_ADDRESS, USDCE_ADDRESS],
          [WAVAX_ADDRESS, USDCE_ADDRESS]
        )
      expect(await this.USDCE.balanceOf(this.alice.address)).to.be.above(0)
    })

    it("zap APEX to APEX/AVAX and zapOutAVAX to APEX", async function () {
      await this.router
        .connect(this.alice)
        .swapExactAVAXForTokens("0", [WAVAX_ADDRESS, APEX_ADDRESS], this.alice.address, ethers.utils.parseEther("0.1"), {
          value: ethers.utils.parseEther("1"),
        })
      const balance = await this.apex.balanceOf(this.alice.address)

      await this.apex.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))

      await this.zapV2.connect(this.alice).zapInToken(balance, 0, 0, [APEX_ADDRESS], [APEX_ADDRESS, WAVAX_ADDRESS])

      expect(await this.avaxApex.balanceOf(this.alice.address)).to.be.above(0)

      await this.avaxApex.connect(this.alice).approve(this.zapV2.address, ethers.utils.parseEther("100"))

      await this.zapV2
        .connect(this.alice)
        .zapOutToken(await this.avaxApex.balanceOf(this.alice.address), 0, [APEX_ADDRESS], [WAVAX_ADDRESS, APEX_ADDRESS])
      expect(await this.apex.balanceOf(this.alice.address)).to.be.above(0)
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

const getAmountOut = async (token, pair) => {
  const reserves = await pair.getReserves()
  const token0 = await pair.token0()

  if (token == token0) {
    return reserves[1].mul(amountIn).div(reserves[0].add(amountIn))
  }
  return reserves[0].mul(amountIn).div(reserves[1].add(amountIn))
}
