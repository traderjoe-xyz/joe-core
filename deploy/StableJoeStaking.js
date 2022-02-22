module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  let rewardToken, joeAddress, feeCollector, depositFeePercent;

  const chainId = await getChainId();
  if (chainId == 4) {
    // rinkeby contract addresses
    joeAddress = ethers.utils.getAddress(
      "0xce347E069B68C53A9ED5e7DA5952529cAF8ACCd4"
    );
    rewardToken = ethers.constants.AddressZero;
    feeCollector = ethers.constants.AddressZero;
    depositFeePercent = 0;
  } else if (chainId == 43114 || chainId == 31337) {
    // avalanche mainnet or hardhat network addresses
    joeAddress = ethers.utils.getAddress(
      "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd"
    );
    rewardToken = ethers.constants.AddressZero;
    feeCollector = ethers.constants.AddressZero;
    depositFeePercent = 0;
  }

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
