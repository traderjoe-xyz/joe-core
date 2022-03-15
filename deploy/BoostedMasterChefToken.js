module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const token = await deploy("BoostedMasterChefToken", {
    from: deployer,
    args: ["BMCJ Token", "BMCJT", "1"],
    log: true,
    contract: "ERC20Mock",
  });
  if (token.newlyDeployed) {
    const dummyToken = await ethers.getContractAt("ERC20Mock", token.address);
    await dummyToken.renounceOwnership();
  }
};

module.exports.tags = ["BoostedMasterChefToken"];
module.exports.dependencies = [];
