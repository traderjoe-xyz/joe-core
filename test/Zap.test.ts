import { ethers, network } from "hardhat"
import { expect } from "chai"
import { prepare, deploy, getBigNumber, createSLP } from "./utilities"

describe("Zap", function () {
  before(async function () {
    await prepare(this, ["ERC20Mock", "JoePair", "Zap"])
  })

  beforeEach(async function () {
    await deploy(this, [
      ["joe", this.ERC20Mock, ["JOE", "JOE", getBigNumber("10000000")]],
      ["wavax", this.ERC20Mock, ["WAVAX", "WAVAX", getBigNumber("10000000")]],
      ["factory", this.JoeFactory, [this.alice.address]],
    ])
    await deploy(this, [["bar", this.JoeBar, [this.joe.address]]])
    await deploy(this, [["joeMaker", this.JoeMaker, [this.factory.address, this.bar.address, this.joe.address, this.wavax.address]]])
    await deploy(this, [["zap", this.Zap, [this.joe.address]]])
    await createSLP(this, "joeAvax", this.joe, this.avax, getBigNumber(10))

  })
  describe("convert", function () {

    it("should swap to token")

    it("should zap token to LP")

    it("should zap out to token")
    
    it("should revert for invalid to address")

    it("should revert for invalid from address")

    it("should revert if no path found")
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
