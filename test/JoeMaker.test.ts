import { ethers, network } from "hardhat"
import { expect } from "chai"
import { prepare, deploy, getBigNumber, createSLP } from "./utilities"

describe("JoeMaker", function () {
  before(async function () {
    await prepare(this, ["JoeMaker", "JoeBar", "JoeMakerExploitMock", "ERC20Mock", "JoeFactory", "JoePair"])
  })

  beforeEach(async function () {
    await deploy(this, [
      ["joe", this.ERC20Mock, ["JOE", "JOE", getBigNumber("10000000")]],
      ["dai", this.ERC20Mock, ["DAI", "DAI", getBigNumber("10000000")]],
      ["mic", this.ERC20Mock, ["MIC", "MIC", getBigNumber("10000000")]],
      ["usdc", this.ERC20Mock, ["USDC", "USDC", getBigNumber("10000000")]],
      ["weth", this.ERC20Mock, ["WETH", "ETH", getBigNumber("10000000")]],
      ["strudel", this.ERC20Mock, ["$TRDL", "$TRDL", getBigNumber("10000000")]],
      ["factory", this.JoeFactory, [this.alice.address]],
    ])
    await deploy(this, [["bar", this.JoeBar, [this.joe.address]]])
    await deploy(this, [["joeMaker", this.JoeMaker, [this.factory.address, this.bar.address, this.joe.address, this.weth.address]]])
    await deploy(this, [["exploiter", this.JoeMakerExploitMock, [this.joeMaker.address]]])
    await createSLP(this, "joeEth", this.joe, this.weth, getBigNumber(10))
    await createSLP(this, "strudelEth", this.strudel, this.weth, getBigNumber(10))
    await createSLP(this, "daiEth", this.dai, this.weth, getBigNumber(10))
    await createSLP(this, "usdcEth", this.usdc, this.weth, getBigNumber(10))
    await createSLP(this, "micUSDC", this.mic, this.usdc, getBigNumber(10))
    await createSLP(this, "joeUSDC", this.joe, this.usdc, getBigNumber(10))
    await createSLP(this, "daiUSDC", this.dai, this.usdc, getBigNumber(10))
    await createSLP(this, "daiMIC", this.dai, this.mic, getBigNumber(10))
  })
  describe("setBridge", function () {
    it("does not allow to set bridge for Joe", async function () {
      await expect(this.joeMaker.setBridge(this.joe.address, this.weth.address)).to.be.revertedWith("JoeMaker: Invalid bridge")
    })

    it("does not allow to set bridge for WETH", async function () {
      await expect(this.joeMaker.setBridge(this.weth.address, this.joe.address)).to.be.revertedWith("JoeMaker: Invalid bridge")
    })

    it("does not allow to set bridge to itself", async function () {
      await expect(this.joeMaker.setBridge(this.dai.address, this.dai.address)).to.be.revertedWith("JoeMaker: Invalid bridge")
    })

    it("emits correct event on bridge", async function () {
      await expect(this.joeMaker.setBridge(this.dai.address, this.joe.address))
        .to.emit(this.joeMaker, "LogBridgeSet")
        .withArgs(this.dai.address, this.joe.address)
    })
  })
  describe("convert", function () {
    it("should convert JOE - ETH", async function () {
      await this.joeEth.transfer(this.joeMaker.address, getBigNumber(1))
      await this.joeMaker.convert(this.joe.address, this.weth.address)
      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joeEth.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("1897569270781234370")
    })

    it("should convert USDC - ETH", async function () {
      await this.usdcEth.transfer(this.joeMaker.address, getBigNumber(1))
      await this.joeMaker.convert(this.usdc.address, this.weth.address)
      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.usdcEth.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("1590898251382934275")
    })

    it("should convert $TRDL - ETH", async function () {
      await this.strudelEth.transfer(this.joeMaker.address, getBigNumber(1))
      await this.joeMaker.convert(this.strudel.address, this.weth.address)
      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.strudelEth.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("1590898251382934275")
    })

    it("should convert USDC - JOE", async function () {
      await this.joeUSDC.transfer(this.joeMaker.address, getBigNumber(1))
      await this.joeMaker.convert(this.usdc.address, this.joe.address)
      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joeUSDC.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("1897569270781234370")
    })

    it("should convert using standard ETH path", async function () {
      await this.daiEth.transfer(this.joeMaker.address, getBigNumber(1))
      await this.joeMaker.convert(this.dai.address, this.weth.address)
      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.daiEth.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("1590898251382934275")
    })

    it("converts MIC/USDC using more complex path", async function () {
      await this.micUSDC.transfer(this.joeMaker.address, getBigNumber(1))
      await this.joeMaker.setBridge(this.usdc.address, this.joe.address)
      await this.joeMaker.setBridge(this.mic.address, this.usdc.address)
      await this.joeMaker.convert(this.mic.address, this.usdc.address)
      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.micUSDC.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("1590898251382934275")
    })

    it("converts DAI/USDC using more complex path", async function () {
      await this.daiUSDC.transfer(this.joeMaker.address, getBigNumber(1))
      await this.joeMaker.setBridge(this.usdc.address, this.joe.address)
      await this.joeMaker.setBridge(this.dai.address, this.usdc.address)
      await this.joeMaker.convert(this.dai.address, this.usdc.address)
      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.daiUSDC.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("1590898251382934275")
    })

    it("converts DAI/MIC using two step path", async function () {
      await this.daiMIC.transfer(this.joeMaker.address, getBigNumber(1))
      await this.joeMaker.setBridge(this.dai.address, this.usdc.address)
      await this.joeMaker.setBridge(this.mic.address, this.dai.address)
      await this.joeMaker.convert(this.dai.address, this.mic.address)
      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.daiMIC.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("1200963016721363748")
    })

    it("reverts if it loops back", async function () {
      await this.daiMIC.transfer(this.joeMaker.address, getBigNumber(1))
      await this.joeMaker.setBridge(this.dai.address, this.mic.address)
      await this.joeMaker.setBridge(this.mic.address, this.dai.address)
      await expect(this.joeMaker.convert(this.dai.address, this.mic.address)).to.be.reverted
    })

    it("reverts if caller is not EOA", async function () {
      await this.joeEth.transfer(this.joeMaker.address, getBigNumber(1))
      await expect(this.exploiter.convert(this.joe.address, this.weth.address)).to.be.revertedWith("JoeMaker: must use EOA")
    })

    it("reverts if pair does not exist", async function () {
      await expect(this.joeMaker.convert(this.mic.address, this.micUSDC.address)).to.be.revertedWith("JoeMaker: Invalid pair")
    })

    it("reverts if no path is available", async function () {
      await this.micUSDC.transfer(this.joeMaker.address, getBigNumber(1))
      await expect(this.joeMaker.convert(this.mic.address, this.usdc.address)).to.be.revertedWith("JoeMaker: Cannot convert")
      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.micUSDC.balanceOf(this.joeMaker.address)).to.equal(getBigNumber(1))
      expect(await this.joe.balanceOf(this.bar.address)).to.equal(0)
    })
  })

  describe("convertMultiple", function () {
    it("should allow to convert multiple", async function () {
      await this.daiEth.transfer(this.joeMaker.address, getBigNumber(1))
      await this.joeEth.transfer(this.joeMaker.address, getBigNumber(1))
      await this.joeMaker.convertMultiple([this.dai.address, this.joe.address], [this.weth.address, this.weth.address])
      expect(await this.joe.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.daiEth.balanceOf(this.joeMaker.address)).to.equal(0)
      expect(await this.joe.balanceOf(this.bar.address)).to.equal("3186583558687783097")
    })
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
