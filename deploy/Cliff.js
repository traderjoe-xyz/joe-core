module.exports = async function ({ ethers, getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer, dev } = await getNamedAccounts();

  const chainId = await getChainId();

  const joe = await ethers.getContract("JoeToken");

  await deploy("Cliff", {
    from: deployer,
    args: [joe.address, dev, 0, 3],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["Cliff"];
module.exports.dependencies = ["JoeToken"];
