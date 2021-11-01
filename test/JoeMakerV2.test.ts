// @ts-ignore
import {ethers, network} from "hardhat"
import {expect} from "chai"
import {createSLP, getBigNumber} from "./utilities";

const JOE_ADDRESS = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd"
const WAVAX_ADDRESS = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7"
const USDT_ADDRESS = "0xc7198437980c041c805A1EDcbA50c1Ce5db95118"
const USDC_ADDRESS = "0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664"
const DAI_ADDRESS = "0xd586E7F844cEa2F87f50152665BCbc2C279D8d70"
const WBTC_ADDRESS = "0x50b7545627a5162F82A992c33b87aDc75187B218"
const LINK_ADDRESS = "0x5947BB275c521040051D82396192181b413227A3"

const FACTORY_ADDRESS = "0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10"
const ZAP_ADDRESS = "0x2C7B8e971c704371772eDaf16e0dB381A8D02027"
const BAR_ADDRESS = "0x57319d41F71E81F3c65F2a47CA4e001EbAFd4F33"

describe("joeMakerV2", function () {
    before(async function () {
        this.joeMakerV2Contract = await ethers.getContractFactory("JoeMakerV2")
        this.ERC20Contract = await ethers.getContractFactory("JoeERC20")
        this.JoePair = await ethers.getContractFactory("Zap")

        this.signers = await ethers.getSigners();
        this.alice = this.signers[0];
        this.bob = this.signers[1];


        this.factory = await ethers.getContractAt("JoeFactory", FACTORY_ADDRESS)
        this.zap = await ethers.getContractAt("Zap", ZAP_ADDRESS, this.alice)

        this.joe = await ethers.getContractAt("JoeERC20", JOE_ADDRESS)
        this.weth = await ethers.getContractAt("JoeERC20", WAVAX_ADDRESS, this.alice)
        this.usdt = await ethers.getContractAt("JoeERC20", USDT_ADDRESS)
        this.usdc = await ethers.getContractAt("JoeERC20", USDC_ADDRESS)
        this.dai = await ethers.getContractAt("JoeERC20", DAI_ADDRESS)
        this.link = await ethers.getContractAt("JoeERC20", LINK_ADDRESS)
        this.wbtc = await ethers.getContractAt("JoeERC20", WBTC_ADDRESS)

        this.joeEth = await ethers.getContractAt("JoeERC20", "0x454E67025631C065d3cFAD6d71E6892f74487a15", this.alice)
        this.linkEth = await ethers.getContractAt("JoeERC20", "0x6F3a0C89f611Ef5dC9d96650324ac633D02265D3", this.alice)
        this.daiEth = await ethers.getContractAt("JoeERC20", "0x87Dee1cC9FFd464B79e058ba20387c1984aed86a", this.alice)
        this.usdcEth = await ethers.getContractAt("JoeERC20", "0xa389f9430876455c36478deea9769b7ca4e3ddb1", this.alice)
        this.linkUSDC = await ethers.getContractAt("JoeERC20", "0xb9f425bc9af072a91c423e31e9eb7e04f226b39d", this.alice)
        this.joeUSDT = await ethers.getContractAt("JoeERC20", "0x1643de2efB8e35374D796297a9f95f64C082a8ce", this.alice)
        this.daiUSDC = await ethers.getContractAt("JoeERC20", "0x63abe32d0ee76c05a11838722a63e012008416e6", this.alice)
        this.wbtcUSDC = await ethers.getContractAt("JoeERC20", "0x62475f52add016a06b398aa3b2c2f2e540d36859", this.alice)
    })

    beforeEach(async function () {
        await network.provider.request({
                method: "hardhat_reset",
                params: [
                    {
                        forking: {
                            jsonRpcUrl: "https://api.avax.network/ext/bc/C/rpc",
                            blockNumber: 6230975,
                        },
                        live: false,
                        saveDeployments: true,
                        tags: ["test", "local"],
                    }
                ],
            }
        )

        this.joeMakerV2 = await this.joeMakerV2Contract.deploy(FACTORY_ADDRESS, BAR_ADDRESS, JOE_ADDRESS, WAVAX_ADDRESS)
        await this.joeMakerV2.deployed()
    })

    describe("setBridge", function () {
        it("does not allow to set bridge for Joe", async function () {
            await expect(this.joeMakerV2.setBridge(this.joe.address, this.weth.address)).to.be.revertedWith("JoeMakerV2: Invalid bridge")
        })

        it("does not allow to set bridge for WETH", async function () {
            await expect(this.joeMakerV2.setBridge(this.weth.address, this.joe.address)).to.be.revertedWith("JoeMakerV2: Invalid bridge")
        })

        it("does not allow to set bridge to itself", async function () {
            await expect(this.joeMakerV2.setBridge(this.dai.address, this.dai.address)).to.be.revertedWith("JoeMakerV2: Invalid bridge")
        })

        it("emits correct event on bridge", async function () {
            await expect(this.joeMakerV2.setBridge(this.dai.address, this.joe.address))
                .to.emit(this.joeMakerV2, "LogBridgeSet")
                .withArgs(this.dai.address, this.joe.address)
        })
    })

    describe("convert", function () {
        it("should convert JOE - ETH", async function () {
            this.zap.zapIn(this.joeEth.address, {value: "2000000000000000000"})
            await this.joeEth.transfer(this.joeMakerV2.address, await this.joeEth.balanceOf(this.alice.address))
            await this.joeMakerV2.convert(this.joe.address, this.weth.address)
            expect(await this.joe.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.joeEth.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("65760783616968116046274051")
        })

        it("should convert USDC - ETH", async function () {
            this.zap.zapIn(this.usdcEth.address, {value: "2000000000000000000"})
            await this.usdcEth.transfer(this.joeMakerV2.address, await this.usdcEth.balanceOf(this.alice.address))
            await this.joeMakerV2.convert(this.usdc.address, this.weth.address)
            expect(await this.joe.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.usdcEth.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("65760783486328184751753372")
        })

        it("should convert LINK - ETH", async function () {
            this.zap.zapIn(this.linkEth.address, {value: "2000000000000000000"})
            await this.linkEth.transfer(this.joeMakerV2.address, await this.linkEth.balanceOf(this.alice.address))
            await this.joeMakerV2.convert(this.link.address, this.weth.address)
            expect(await this.joe.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.linkEth.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("65760783486363859028081484")
        })

        it("should convert USDT - JOE", async function () {
            this.zap.zapIn(this.joeUSDT.address, {value: "2000000000000000000"})
            await this.joeUSDT.transfer(this.joeMakerV2.address, await this.joeUSDT.balanceOf(this.alice.address))
            await this.joeMakerV2.convert(this.usdt.address, this.joe.address)
            expect(await this.joe.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.joeUSDT.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("65760783453156517296637229")
        })

        it("should convert using standard ETH path", async function () {
            this.zap.zapIn(this.daiEth.address, {value: "2000000000000000000"})
            await this.daiEth.transfer(this.joeMakerV2.address, await this.daiEth.balanceOf(this.alice.address))
            await this.joeMakerV2.convert(this.dai.address, this.weth.address)
            expect(await this.joe.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.daiEth.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("65760783486391030415691929")
        })

        it("converts LINK/USDC using more complex path", async function () {
            this.zap.zapIn(this.linkUSDC.address, {value: "2000000000000000000"})
            await this.linkUSDC.transfer(this.joeMakerV2.address, await this.linkUSDC.balanceOf(this.alice.address))
            await this.joeMakerV2.setBridge(this.usdt.address, this.joe.address)
            await this.joeMakerV2.setBridge(this.usdc.address, this.usdt.address)
            await this.joeMakerV2.convert(this.link.address, this.usdc.address)
            expect(await this.joe.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.linkUSDC.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("65760783310814022468214801")
        })

        it("converts DAI/USDC using more complex path", async function () {
            this.zap.zapIn(this.daiUSDC.address, {value: "2000000000000000000"})
            await this.daiUSDC.transfer(this.joeMakerV2.address, await this.daiUSDC.balanceOf(this.alice.address))
            await this.joeMakerV2.setBridge(this.usdc.address, this.joe.address)
            await this.joeMakerV2.setBridge(this.dai.address, this.usdc.address)
            await this.joeMakerV2.convert(this.dai.address, this.usdc.address)
            expect(await this.joe.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.daiUSDC.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("65760783292069323759758118")
        })

        it("reverts if it loops back", async function () {
            this.zap.zapIn(this.daiUSDC.address, {value: "2000000000000000000"})
            await this.daiUSDC.transfer(this.joeMakerV2.address, await this.wbtcUSDC.balanceOf(this.alice.address))
            await this.joeMakerV2.setBridge(this.dai.address, this.usdc.address)
            await this.joeMakerV2.setBridge(this.usdc.address, this.dai.address)
            await expect(this.joeMakerV2.convert(this.dai.address, this.usdc.address)).to.be.reverted
        })

        // it("reverts if caller is not EOA", async function () {
        //     this.zap.zapIn(this.joeEth.address, {value: "2000000000000000000"})
        //     await this.joeEth.transfer(this.joeMakerV2.address, await this.joeEth.balanceOf(this.alice.address))
        //     await expect(this.exploiter.convert(this.joe.address, this.weth.address)).to.be.revertedWith("JoeMakerV2: must use EOA")
        // })

        it("reverts if pair does not exist", async function () {
            await expect(this.joeMakerV2.convert(this.joe.address, this.joeEth.address)).to.be.revertedWith("JoeMakerV2: Invalid pair")
        })

        // it("reverts if no path is available", async function () {
        //     const previousBalance = await this.joe.balanceOf(BAR_ADDRESS)
        //     this.zap.zapIn(this.daiUSDC.address, {value: "2000000000000000000"})
        //     await this.daiUSDC.transfer(this.joeMakerV2.address, await this.daiUSDC.balanceOf(this.alice.address))
        //     await expect(this.joeMakerV2.convert(this.dai.address, this.usdc.address)).to.be.revertedWith("JoeMakerV2: Cannot convert")
        //     expect(await this.joe.balanceOf(this.joeMakerV2.address)).to.equal(0)
        //     expect(await this.daiUSDC.balanceOf(this.joeMakerV2.address)).to.equal(await this.daiUSDC.balanceOf(this.alice.address))
        //     expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal(previousBalance)
        // })
    })

    describe("convertMultiple", function () {
        it("should allow to convert multiple", async function () {
            this.zap.zapIn(this.daiEth.address, {value: "2000000000000000000"})
            this.zap.zapIn(this.joeEth.address, {value: "2000000000000000000"})
            await this.daiEth.transfer(this.joeMakerV2.address, await this.daiEth.balanceOf(this.alice.address))
            await this.joeEth.transfer(this.joeMakerV2.address, await this.joeEth.balanceOf(this.alice.address))
            await this.joeMakerV2.convertMultiple([this.dai.address, this.joe.address], [this.weth.address, this.weth.address])
            expect(await this.joe.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.daiEth.balanceOf(this.joeMakerV2.address)).to.equal(0)
            expect(await this.joe.balanceOf(BAR_ADDRESS)).to.equal("65760827030716841768075277")
        })
    })

    after(async function () {
        await network.provider.request({
            method: "hardhat_reset",
            params: [],
        })
    })
})
