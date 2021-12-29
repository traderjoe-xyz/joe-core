// Deploy for testing of MasterChefJoeV2
module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const rewardToken = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7";
  const lpToken = "0xb97F23A9e289B5F5e8732b6e20df087977AcC434";
  const mcj = "0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00";

  await deploy("SimpleRewarderPerSec", {
    from: deployer,
    args: [rewardToken, lpToken, "0", mcj, true],
    gasLmit: 22000000000,
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["SimpleRewarderPerSec"];
