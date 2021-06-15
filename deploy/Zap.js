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
  const joe = await deployments.get("JoeToken");
  const router = await deployments.get("JoeRouter02");
  await zap.initialize(joe.address, router.address);
};

module.exports.tags = ["Zap"];
module.exports.dependencies = ["JoeRouter02", "JoeToken"];
