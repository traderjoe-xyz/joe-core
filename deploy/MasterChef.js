// Deploy for testing of MasterChefJoeV2 only
module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;

  const { deployer, dev } = await getNamedAccounts();

  const sushi = await ethers.getContract("SushiToken");

  const { address } = await deploy("MasterChef", {
    from: deployer,
    args: [
      sushi.address,
      dev,
      "1000000000000000000000",
      "0",
      "1000000000000000000000",
    ],
    log: true,
    deterministicDeployment: false,
  });

  if ((await sushi.owner()) !== address) {
    // Transfer Sushi Ownership to Chef
    console.log("Transfer Sushi Ownership to Chef");
    await (await sushi.transferOwnership(address)).wait();
  }
};

module.exports.tags = ["MasterChef"];
module.exports.dependencies = ["SushiToken"];
