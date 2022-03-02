module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const { address } = await deploy("BoostedMasterChefToken", {
    from: deployer,
    args: ["BMCJ Token", "BMCJT", "1"],
    log: true,
    contract: "ERC20Mock",
  });
  const dummyToken = await ethers.getContractAt("ERC20Mock", address);
  await dummyToken.renounceOwnership();
};

module.exports.tags = ["BoostedMasterChefToken"];
module.exports.dependencies = [];
