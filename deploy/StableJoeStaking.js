module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  let rewardToken, joeAddress, feeCollector, depositFeePercent;

  const chainId = await getChainId();
  if (chainId == 4) {
    // rinkeby contract addresses
    joeAddress = "0xce347E069B68C53A9ED5e7DA5952529cAF8ACCd4";
    feeCollector = "0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2";
    depositFeePercent = 0;
  } else if (chainId == 43114 || chainId == 31337) {
    // avalanche mainnet or hardhat network addresses
    joeAddress = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd";
    feeCollector = "0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2";
    depositFeePercent = 0;
  }
  rewardToken = joeAddress;

  const stableJoeStaking = await deploy("StableJoeStaking", {
    from: deployer,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [rewardToken, joeAddress, feeCollector, depositFeePercent],
        },
      },
    },
    log: true,
  });
};

module.exports.tags = ["StableJoeStaking"];
module.exports.dependencies = [];
