import { ethers, network } from "hardhat"
const { duration, increase } = require("./utilities/time")

const BMCJ_ADDRESS = "0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F"
const FL2_ADDRESS = "0xF16d25Eba0D8E51cEAF480141bAf577aE55bfdd2"
const JOE_ADDRESS = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd"
const VEJOE_ADDRESS = "0x3cabf341943Bc8466245e4d6F1ae0f8D071a1456"

const USER_ADDRESS = "0x3876183b75916e20d2ADAB202D1A3F9e9bf320ad"

describe.only("BoostedMasterChefJoe", function () {
  beforeEach(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: "https://api.avax.network/ext/bc/C/rpc",
            blockNumber: 13104831,
          },
          live: false,
          saveDeployments: false,
          tags: ["test", "local"],
        },
      ],
    })

    this.bmcj = await ethers.getContractAt("BoostedMasterChefJoe", BMCJ_ADDRESS)
    this.fl2 = await ethers.getContractAt("FarmLensV2", FL2_ADDRESS)

    this.joe = await ethers.getContractAt("JoeToken", JOE_ADDRESS)
    this.vejoe = await ethers.getContractAt("VeJoeToken", VEJOE_ADDRESS)

    // Accounts
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [USER_ADDRESS],
    })
    this.user = await ethers.provider.getSigner(USER_ADDRESS)
  })

  it("Verify APR", async function () {
    const pid = 8
    const res = await this.fl2.getBMCJFarmInfos(BMCJ_ADDRESS, USER_ADDRESS, [pid])
    const base = res[0].baseApr
    const boost = res[0].userBoostedApr
    const joePrice = res[0].joePriceUsd
    const userLpUsd = res[0].userLp.mul(res[0].reserveUsd).div(res[0].totalSupplyScaled)

    console.log("aprs:", base / 1e16, boost / 1e16)

    console.log("expected Apr:", base.add(boost) / 1e16)

    await this.bmcj.connect(this.user).withdraw(pid, 0)
    const joeBalance = await this.joe.balanceOf(this.user._address)

    await increase(duration.days(365))

    await this.bmcj.connect(this.user).withdraw(pid, 0)

    const joeUsd = (await this.joe.balanceOf(this.user._address)).sub(joeBalance).mul(joePrice).div(ethers.utils.parseEther("1"))
    console.log("actual Apr:", (joeUsd / userLpUsd) * 100)
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
