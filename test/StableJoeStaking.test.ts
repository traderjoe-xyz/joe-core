import { ethers, network } from "hardhat"
import { expect } from "chai"
import { describe } from "mocha"
const hre = require("hardhat")

describe("Stable Joe Staking", function () {
  before(async function () {
    this.StableJoeStakingCF = await ethers.getContractFactory("StableJoeStaking")
    this.JoeTokenCF = await ethers.getContractFactory("JoeToken")

    this.signers = await ethers.getSigners()
    this.dev = this.signers[0]
    this.alice = this.signers[1]
    this.bob = this.signers[2]
    this.carol = this.signers[3]
    this.joeMaker = this.signers[4]
  })

  beforeEach(async function () {
    this.rewardToken = await this.JoeTokenCF.deploy()
    this.joe = await this.JoeTokenCF.deploy()

    await this.joe.mint(this.alice.address, ethers.utils.parseEther("1000"))
    await this.joe.mint(this.bob.address, ethers.utils.parseEther("1000"))
    await this.joe.mint(this.carol.address, ethers.utils.parseEther("1000"))
    await this.rewardToken.mint(this.joeMaker.address, ethers.utils.parseEther("1000000")) // 1_000_000 tokens

    const block = await ethers.provider.getBlock("latest")
    // Make sure we start the tests at 23:59:00
    await increase(2 * 86400 - (block.timestamp % 86400) - 60)

    this.sJoe = await hre.upgrades.deployProxy(this.StableJoeStakingCF, [this.rewardToken.address, this.joe.address])

    await this.joe.connect(this.alice).approve(this.sJoe.address, ethers.utils.parseEther("100000"))
    await this.joe.connect(this.bob).approve(this.sJoe.address, ethers.utils.parseEther("100000"))
    await this.joe.connect(this.carol).approve(this.sJoe.address, ethers.utils.parseEther("100000"))
  })

  describe("should allow deposits and withdraws", function () {
    it("should allow deposits and withdraws of multiple users", async function () {
      await this.sJoe.connect(this.alice).deposit(ethers.utils.parseEther("100"))
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("900"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("100"))

      await this.sJoe.connect(this.bob).deposit(ethers.utils.parseEther("200"))
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(ethers.utils.parseEther("800"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("300"))

      await this.sJoe.connect(this.carol).deposit(ethers.utils.parseEther("300"))
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(ethers.utils.parseEther("700"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("600"))

      await this.sJoe.connect(this.alice).withdraw(ethers.utils.parseEther("100"))
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("1000"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("500"))

      await this.sJoe.connect(this.carol).withdraw(ethers.utils.parseEther("100"))
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(ethers.utils.parseEther("800"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("400"))

      await this.sJoe.connect(this.bob).withdraw("1")
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(ethers.utils.parseEther("800.000000000000000001"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("399.999999999999999999"))
    })

    it("should update variables accordingly", async function () {
      await this.sJoe.connect(this.alice).deposit("1")

      await this.rewardToken.connect(this.joeMaker).transfer(this.sJoe.address, ethers.utils.parseEther("86400"))
      expect(await this.rewardToken.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("86400"))
      expect(await this.sJoe.lastRewardBalance()).to.be.equal("0")
      expect(await this.sJoe.tokensPerSec()).to.be.equal("0")

      await increase(3 * 3600)
      let block = await ethers.provider.getBlock("latest")

      // As we sent 86400 tokens to sJoe, tokensPerSec = 1
      // Alice is the only one that deposited, so she owns all the rewards.
      //
      // But previous day, `tokensPerSec = 0`, so she will receive no reward from day 0
      // and only rewards from day 1, hence `currentTimeStamp - lastDayTimestampAt0`
      // which is equal to `currentTimeStamp % 1 days` cause `currentTimeStamp = lastDayTimestampAt0 + elapsedSecondOfCurrentDay`
      expect(await this.rewardToken.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("86400"))
      expect(await this.sJoe.pendingTokens(this.alice.address)).to.be.equal(ethers.utils.parseEther("1").mul(block.timestamp % 86400))

      // Making sure that `pendingTokens` still return the accurate tokens even after updating pools
      await this.sJoe.updatePool()
      block = await ethers.provider.getBlock("latest")
      expect(await this.sJoe.pendingTokens(this.alice.address)).to.be.equal(ethers.utils.parseEther("1").mul(block.timestamp % 86400))

      await increase(86_400)

      // Should be equal to 86400e18
      expect(await this.sJoe.pendingTokens(this.alice.address)).to.be.equal(ethers.utils.parseEther("86400"))

      // Making sure that `pendingTokens` still return the accurate tokens even after updating pools
      await this.sJoe.updatePool()
      expect(await this.sJoe.pendingTokens(this.alice.address)).to.be.equal(ethers.utils.parseEther("86400"))
    })

    it("should allow deposits and withdraws of multiple users and distribute rewards accordingly", async function () {
      await this.sJoe.connect(this.alice).deposit(ethers.utils.parseEther("100"))
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("900"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("100"))

      await this.sJoe.connect(this.bob).deposit(ethers.utils.parseEther("200"))
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(ethers.utils.parseEther("800"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("300"))

      await this.sJoe.connect(this.carol).deposit(ethers.utils.parseEther("300"))
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(ethers.utils.parseEther("700"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("600"))

      await this.rewardToken.connect(this.joeMaker).transfer(this.sJoe.address, ethers.utils.parseEther("518400")) // 6 * 86_400, tokensPerSec is 6
      await this.sJoe.updatePool()
      await increase(86_400 + 60)

      await this.sJoe.connect(this.alice).withdraw(ethers.utils.parseEther("100"))
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("1000"))
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("86400"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("500"))

      await this.sJoe.connect(this.carol).withdraw(ethers.utils.parseEther("100"))
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(ethers.utils.parseEther("800"))
      expect(await this.rewardToken.balanceOf(this.carol.address)).to.be.equal(ethers.utils.parseEther("259200")) // 3 * 86_400
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("400"))

      await this.sJoe.connect(this.bob).withdraw("0")
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(ethers.utils.parseEther("800"))
      expect(await this.rewardToken.balanceOf(this.bob.address)).to.be.equal(ethers.utils.parseEther("172800")) // 2 * 86400
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("400"))
    })

    it("should distribute token accordingly even if update isn't called every day", async function () {
      await this.rewardToken.connect(this.joeMaker).transfer(this.sJoe.address, ethers.utils.parseEther("86400")) // 6 * 86_400, tokensPerSec is 6

      await this.sJoe.connect(this.alice).deposit(1)
      await increase(10 * 86_400)

      await this.sJoe.connect(this.alice).withdraw(0)
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("86400"))

      await this.rewardToken.connect(this.joeMaker).transfer(this.sJoe.address, ethers.utils.parseEther("86400")) // 6 * 86_400, tokensPerSec is 6
      await increase(10 * 86_400)

      await this.sJoe.connect(this.alice).withdraw(0)
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("172800"))
    })

    it("should allow deposits and withdraws of multiple users and distribute rewards accordingly even if someone enters or leaves", async function () {
      await this.sJoe.connect(this.alice).deposit(ethers.utils.parseEther("100"))
      await this.sJoe.connect(this.carol).deposit(ethers.utils.parseEther("100"))
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("900"))
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(ethers.utils.parseEther("900"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("200"))

      await increase(3600)
      await this.rewardToken.connect(this.joeMaker).transfer(this.sJoe.address, ethers.utils.parseEther("345600")) // 4 * 86400
      await this.sJoe.updatePool()
      await increase(86_400)

      await this.sJoe.connect(this.bob).deposit(ethers.utils.parseEther("200")) // Bob enters
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(ethers.utils.parseEther("800"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("400"))

      await this.sJoe.connect(this.carol).withdraw(ethers.utils.parseEther("100"))
      expect(await this.joe.balanceOf(this.carol.address)).to.be.equal(ethers.utils.parseEther("1000"))
      expect(await this.rewardToken.balanceOf(this.carol.address)).to.be.equal(
        ethers.utils.parseEther("172800") // 2 * 86400
      )
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("300"))

      await this.sJoe.connect(this.alice).deposit(ethers.utils.parseEther("100")) // Alice enters again to try to get more rewards
      await this.sJoe.connect(this.alice).withdraw(ethers.utils.parseEther("200"))
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("1000"))
      // She gets the same reward as Carol, and a bit more as some time elapsed
      const aliceBalance = await this.rewardToken.balanceOf(this.alice.address)
      expect(aliceBalance).to.be.equal(ethers.utils.parseEther("172800")) // 2 * 86400
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("200"))

      await this.rewardToken.connect(this.joeMaker).transfer(this.sJoe.address, ethers.utils.parseEther("86400"))
      await increase(172_800) // 2 days

      await this.sJoe.connect(this.bob).withdraw("0")
      expect(await this.joe.balanceOf(this.bob.address)).to.be.equal(ethers.utils.parseEther("800"))
      expect(await this.rewardToken.balanceOf(this.bob.address)).to.be.equal(
        ethers.utils.parseEther("86400") // 86400
      )
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("200"))

      await this.sJoe.connect(this.alice).withdraw("0") // Alice shouldn't receive any token of the last reward
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("1000"))
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(aliceBalance)
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("200"))
    })

    it("pending tokens function should return the same number of token that user actually receive", async function () {
      await this.sJoe.connect(this.alice).deposit(ethers.utils.parseEther("300"))
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("700"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("300"))

      await this.rewardToken.mint(this.sJoe.address, ethers.utils.parseEther("100")) // We send 100 Tokens to sJoe's address

      const pendingReward = await this.sJoe.pendingTokens(this.alice.address)
      await this.sJoe.connect(this.alice).withdraw("0") // Alice shouldn't receive any token of the last reward
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("700"))
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(pendingReward)
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("300"))
    })

    it("should allow emergency withdraw", async function () {
      await this.sJoe.connect(this.alice).deposit(ethers.utils.parseEther("300"))
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("700"))
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(ethers.utils.parseEther("300"))

      await this.rewardToken.mint(this.sJoe.address, ethers.utils.parseEther("100")) // We send 100 Tokens to sJoe's address

      await this.sJoe.connect(this.alice).emergencyWithdraw() // Alice shouldn't receive any token of the last reward
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(ethers.utils.parseEther("1000"))
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(0)
      expect(await this.joe.balanceOf(this.sJoe.address)).to.be.equal(0)
      const userInfo = await this.sJoe.userInfo(this.sJoe.address)
      expect(userInfo.amount).to.be.equal(0)
      expect(userInfo.rewardDebt).to.be.equal(0)
    })
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})

const increase = (seconds) => {
  ethers.provider.send("evm_increaseTime", [seconds])
  ethers.provider.send("evm_mine", [])
}
