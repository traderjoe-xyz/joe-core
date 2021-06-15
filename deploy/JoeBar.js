module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const joe = await deployments.get("JoeToken");

  await deploy("JoeBar", {
    from: deployer,
    args: [joe.address],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["JoeBar"];
module.exports.dependencies = ["JoeFactory", "JoeRouter02", "JoeToken"];
