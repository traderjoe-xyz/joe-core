module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("BoringCryptoTokenScanner", {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["BoringCryptoTokenScanner", "boring"];
