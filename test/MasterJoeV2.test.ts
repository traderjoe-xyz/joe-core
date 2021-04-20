import { expect, assert } from "chai";
import { advanceBlockTo, advanceBlock, prepare, deploy, getBigNumber, ADDRESS_ZERO } from "./utilities"

describe("MasterChefV2", function () {
  before(async function () {
    await prepare(this, ['MasterChef', 'JoeToken', 'ERC20Mock', 'MasterChefV2', 'RewarderMock', 'RewarderBrokenMock'])
    await deploy(this, [
      ["brokenRewarder", this.RewarderBrokenMock]
    ])
  })

  beforeEach(async function () {
    await deploy(this, [
      ["joe", this.JoeToken],
    ])

    await deploy(this,
      [["lp", this.ERC20Mock, ["LP Token", "LPT", getBigNumber(10)]],
      ["dummy", this.ERC20Mock, ["Dummy", "DummyT", getBigNumber(10)]],
      ['chef', this.MasterChef, [this.joe.address, this.bob.address, getBigNumber(100), "0", "0"]]
    ])

    await this.joe.transferOwnership(this.chef.address)
    await this.chef.add(100, this.lp.address, true)
    await this.chef.add(100, this.dummy.address, true)
    await this.lp.approve(this.chef.address, getBigNumber(10))
    await this.chef.deposit(0, getBigNumber(10))

    await deploy(this, [
        ['chef2', this.MasterChefV2, [this.chef.address, this.joe.address, 1]],
        ["rlp", this.ERC20Mock, ["LP", "rLPT", getBigNumber(10)]],
        ["r", this.ERC20Mock, ["Reward", "RewardT", getBigNumber(100000)]],
    ])
    await deploy(this, [["rewarder", this.RewarderMock, [getBigNumber(1), this.r.address]]])
    await this.dummy.approve(this.chef2.address, getBigNumber(10))
    await this.chef2.init(this.dummy.address)
    await this.rlp.transfer(this.bob.address, getBigNumber(1))
  })

  describe("Init", function () {
    it("Balance of dummyToken should be 0 after init(), repeated execution should fail", async function () {
      await expect(this.chef2.init(this.dummy.address))
            .to.be.revertedWith("Balance must exceed 0")
    })
  })

  describe("PoolLength", function () {
    it("PoolLength should execute", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address)
      expect((await this.chef2.poolLength())).to.be.equal(1);
    })
  })

  describe("Set", function() {
    it("Should emit event LogSetPool", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address)
      await expect(this.chef2.set(0, 10, this.dummy.address, false))
            .to.emit(this.chef2, "LogSetPool")
            .withArgs(0, 10, this.rewarder.address, false)
      await expect(this.chef2.set(0, 10, this.dummy.address, true))
            .to.emit(this.chef2, "LogSetPool")
            .withArgs(0, 10, this.dummy.address, true)
      })

    it("Should revert if invalid pool", async function () {
      let err;
      try {
        await this.chef2.set(0, 10, this.rewarder.address, false)
      } catch (e) {
        err = e;
      }

      assert.equal(err.toString(), "Error: VM Exception while processing transaction: invalid opcode")
    })
  })

  describe("PendingJoe", function() {
    it("PendingJoe should equal ExpectedJoe", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      let log = await this.chef2.deposit(0, getBigNumber(1), this.alice.address)
      await advanceBlock()
      let log2 = await this.chef2.updatePool(0)
      await advanceBlock()
      let expectedJoe = getBigNumber(100).mul(log2.blockNumber + 1 - log.blockNumber).div(2)
      let pendingJoe = await this.chef2.pendingJoe(0, this.alice.address)
      expect(pendingJoe).to.be.equal(expectedJoe)
    })
    it("When block is lastRewardBlock", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      let log = await this.chef2.deposit(0, getBigNumber(1), this.alice.address)
      await advanceBlockTo(3)
      let log2 = await this.chef2.updatePool(0)
      let expectedJoe = getBigNumber(100).mul(log2.blockNumber - log.blockNumber).div(2)
      let pendingJoe = await this.chef2.pendingJoe(0, this.alice.address)
      expect(pendingJoe).to.be.equal(expectedJoe)
    })
  })

  describe("MassUpdatePools", function () {
    it("Should call updatePool", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address)
      await advanceBlockTo(1)
      await this.chef2.massUpdatePools([0])
      //expect('updatePool').to.be.calledOnContract(); //not suported by heardhat
      //expect('updatePool').to.be.calledOnContractWith(0); //not suported by heardhat

    })

    it("Updating invalid pools should fail", async function () {
      let err;
      try {
        await this.chef2.massUpdatePools([0, 10000, 100000])
      } catch (e) {
        err = e;
      }

      assert.equal(err.toString(), "Error: VM Exception while processing transaction: invalid opcode")
    })
})

  describe("Add", function () {
    it("Should add pool with reward token multiplier", async function () {
      await expect(this.chef2.add(10, this.rlp.address, this.rewarder.address))
            .to.emit(this.chef2, "LogPoolAddition")
            .withArgs(0, 10, this.rlp.address, this.rewarder.address)
      })
  })

  describe("UpdatePool", function () {
    it("Should emit event LogUpdatePool", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address)
      await advanceBlockTo(1)
      await expect(this.chef2.updatePool(0))
            .to.emit(this.chef2, "LogUpdatePool")
            .withArgs(0, (await this.chef2.poolInfo(0)).lastRewardBlock,
              (await this.rlp.balanceOf(this.chef2.address)),
              (await this.chef2.poolInfo(0)).accJoePerShare)
    })

    it("Should take else path", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address)
      await advanceBlockTo(1)
      await this.chef2.batch(
          [
              this.chef2.interface.encodeFunctionData("updatePool", [0]),
              this.chef2.interface.encodeFunctionData("updatePool", [0]),
          ],
          true
      )
    })
  })

  describe("Deposit", function () {
    it("Depositing 0 amount", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      await expect(this.chef2.deposit(0, getBigNumber(0), this.alice.address))
            .to.emit(this.chef2, "Deposit")
            .withArgs(this.alice.address, 0, 0, this.alice.address)
    })

    it("Depositing into non-existent pool should fail", async function () {
      let err;
      try {
        await this.chef2.deposit(1001, getBigNumber(0), this.alice.address)
      } catch (e) {
        err = e;
      }

      assert.equal(err.toString(), "Error: VM Exception while processing transaction: invalid opcode")
    })
  })

  describe("Withdraw", function () {
    it("Withdraw 0 amount", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address)
      await expect(this.chef2.withdraw(0, getBigNumber(0), this.alice.address))
            .to.emit(this.chef2, "Withdraw")
            .withArgs(this.alice.address, 0, 0, this.alice.address)
    })
  })

  describe("Harvest", function () {
    it("Should give back the correct amount of JOE and reward", async function () {
        await this.r.transfer(this.rewarder.address, getBigNumber(100000))
        await this.chef2.add(10, this.rlp.address, this.rewarder.address)
        await this.rlp.approve(this.chef2.address, getBigNumber(10))
        expect(await this.chef2.lpToken(0)).to.be.equal(this.rlp.address)
        let log = await this.chef2.deposit(0, getBigNumber(1), this.alice.address)
        await advanceBlockTo(20)
        await this.chef2.harvestFromMasterChef()
        let log2 = await this.chef2.withdraw(0, getBigNumber(1), this.alice.address)
        let expectedJoe = getBigNumber(100).mul(log2.blockNumber - log.blockNumber).div(2)
        expect((await this.chef2.userInfo(0, this.alice.address)).rewardDebt).to.be.equal("-"+expectedJoe)
        await this.chef2.harvest(0, this.alice.address)
        expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(await this.r.balanceOf(this.alice.address)).to.be.equal(expectedJoe)
    })

    it("Harvest with empty user balance", async function () {
      await this.chef2.add(10, this.rlp.address, this.rewarder.address)
      await this.chef2.harvest(0, this.alice.address)
    })

    it("Harvest for JOE-only pool", async function () {
      await this.chef2.add(10, this.rlp.address, ADDRESS_ZERO)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      expect(await this.chef2.lpToken(0)).to.be.equal(this.rlp.address)
      let log = await this.chef2.deposit(0, getBigNumber(1), this.alice.address)
      await advanceBlock()
      await this.chef2.harvestFromMasterChef()
      let log2 = await this.chef2.withdraw(0, getBigNumber(1), this.alice.address)
      let expectedJoe = getBigNumber(100).mul(log2.blockNumber - log.blockNumber).div(2)
      expect((await this.chef2.userInfo(0, this.alice.address)).rewardDebt).to.be.equal("-"+expectedJoe)
      await this.chef2.harvest(0, this.alice.address)
      expect(await this.joe.balanceOf(this.alice.address)).to.be.equal(expectedJoe)
    })
  })

  describe("EmergencyWithdraw", function() {
    it("Should emit event EmergencyWithdraw", async function () {
      await this.r.transfer(this.rewarder.address, getBigNumber(100000))
      await this.chef2.add(10, this.rlp.address, this.rewarder.address)
      await this.rlp.approve(this.chef2.address, getBigNumber(10))
      await this.chef2.deposit(0, getBigNumber(1), this.bob.address)
      //await this.chef2.emergencyWithdraw(0, this.alice.address)
      await expect(this.chef2.connect(this.bob).emergencyWithdraw(0, this.bob.address))
      .to.emit(this.chef2, "EmergencyWithdraw")
      .withArgs(this.bob.address, 0, getBigNumber(1), this.bob.address)
    })
  })
})
