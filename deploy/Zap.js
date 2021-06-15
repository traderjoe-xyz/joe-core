module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("Zap", {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: false,
  });

  const zap = await ethers.getContract("Zap");
  await zap.initialize();
};

module.exports.tags = ["Zap"];
module.exports.dependencies = ["JoeFactory", "JoeRouter02", "JoeToken"];
