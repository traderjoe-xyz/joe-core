module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;

  const { deployer, dev, treasury } = await getNamedAccounts();

  const joe = await ethers.getContract("JoeToken");

  const { address } = await deploy("MasterChefJoeV2", {
    from: deployer,
    args: [
      joe.address,
      dev,
      treasury,
      "30000000000000000000", // 30 JOE per sec
      "1625335200", // Sat Jul 03 10:00
      "200", // 20%
      "200", // 20%
    ],
    log: true,
    deterministicDeployment: false,
  });

  // if ((await joe.owner()) !== address) {
  //   // Transfer Joe Ownership to MasterChefJoeV2
  //   console.log("Transfer Joe Ownership to MasterChefJoeV2");
  //   await (await joe.transferOwnership(address)).wait();
  // }
};

module.exports.tags = ["MasterChefJoeV2", "chef"];
module.exports.dependencies = ["JoeFactory", "JoeRouter02", "JoeToken"];
