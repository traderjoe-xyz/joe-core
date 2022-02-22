module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("VeJoeToken", {
    from: deployer,
    log: true,
  });
};

module.exports.tags = ["VeJoeToken"];
module.exports.dependencies = [];
