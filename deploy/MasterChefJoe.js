module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;

  const { deployer, dev, treasury } = await getNamedAccounts();

  const joe = await ethers.getContract("JoeToken");

  const { address } = await deploy("MasterChefJoe", {
    from: deployer,
    args: [
      joe.address,
      dev,
      treasury,
      "100000000000000000000",
      "1619065864",
      "200",
      "200",
    ],
    log: true,
    deterministicDeployment: false,
  });

  // if ((await joe.owner()) !== address) {
  //   // Transfer Joe Ownership to Joe
  //   console.log("Transfer Joe Ownership to Joe");
  //   await (await joe.transferOwnership(address)).wait();
  // }
};

module.exports.tags = ["MasterChefJoe"];
module.exports.dependencies = ["JoeFactory", "JoeRouter02", "JoeToken"];
