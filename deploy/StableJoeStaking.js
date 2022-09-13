module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy, catchUnknownSigner } = deployments;
  const { deployer } = await getNamedAccounts();

  let rewardToken,
    joeAddress,
    feeCollector,
    depositFeePercent,
    smolJoes,
    proxyOwner;

  const chainId = await getChainId();
  if (chainId == 4) {
    // rinkeby contract addresses
    joeAddress = "0xce347E069B68C53A9ED5e7DA5952529cAF8ACCd4";
    // fish token
    rewardToken = "0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10";
    feeCollector = "0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2";
    depositFeePercent = 0;
    smolJoes = "0xce347E069B68C53A9ED5e7DA5952529cAF8ACCd4"; // use an ERC20 as placeholder for now
    proxyOwner = deployer;
  } else if (chainId == 43114 || chainId == 31337) {
    // avalanche mainnet or hardhat network addresses
    joeAddress = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd";
    // USDC.e
    rewardToken = "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E";
    feeCollector = "0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2";
    depositFeePercent = 0;
    smolJoes = "0xC70DF87e1d98f6A531c8E324C9BCEC6FC82B5E8d";
    proxyOwner = "0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2";
  }

  await catchUnknownSigner(async () => {
    const sJoe = await deploy("StableJoeStaking", {
      from: deployer,
      proxy: {
        owner: proxyOwner,
        proxyContract: "OpenZeppelinTransparentProxy",
        execute: {
          init: {
            methodName: "initialize",
            args: [
              rewardToken,
              joeAddress,
              feeCollector,
              depositFeePercent,
              smolJoes,
            ],
          },
        },
      },
      log: true,
    });
    if (sJoe.newlyDeployed) {
      console.log("Initializing implementation for safe measure...");
      const sJoeImpl = await ethers.getContract(
        "StableJoeStaking_Implementation"
      );
      await sJoeImpl.initialize(
        rewardToken,
        joeAddress,
        feeCollector,
        depositFeePercent,
        smolJoes
      );
      console.log("Setting Smol Joes...");
      const sJoeProxy = await ethers.getContract("StableJoeStaking");
      await sJoeProxy.setSmolJoes(smolJoes);
    }
  });
};

module.exports.tags = ["StableJoeStaking"];
module.exports.dependencies = [];
