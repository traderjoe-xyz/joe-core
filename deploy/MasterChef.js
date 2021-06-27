// Deploy for testing of MasterChefJoeV2
module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;

  const { deployer, dev, treasury } = await getNamedAccounts();

  const sushi = await ethers.getContract("SushiToken");

  const { address } = await deploy("MasterChef", {
    from: deployer,
    args: [
      sushi.address,
      dev,
      "100000000000000000000",
      "0",
      "1000000000000000000000",
    ],
    log: true,
    deterministicDeployment: false,
  });

  if ((await sushi.owner()) !== address) {
    // Transfer Sushi Ownership to MasterChef
    console.log("Transfer Sushi Ownership to MasterChef");
    await (await sushi.transferOwnership(address)).wait();
  }
};

module.exports.tags = ["MasterChef", "double"];
module.exports.dependencies = ["SushiToken"];
