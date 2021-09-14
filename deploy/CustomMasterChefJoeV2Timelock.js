module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chef = await ethers.getContract("MasterChefJoeV2");

  const { address } = await deploy("CustomMasterChefJoeV2Timelock", {
    from: deployer,
    args: [
      deployer,
      "43200", // 12 hours = 60*60*12 = 43200
      "200", // devPercent limit
      "200", // treasuryPercent limit
      "100", // investorPercent limit
      "40000000000000000000", // joePerSec limit
    ],
    log: true,
    deterministicDeployment: false,
    gasLimit: 4000000,
  });

  // if ((await chef.owner()) !== address) {
  //   // Transfer MasterChefJoeV2 Ownership to timelock
  //   console.log("Transfer MasterChefJoeV2 Ownership to timelock");
  //   await (await chef.transferOwnership(address)).wait();
  // }
};

module.exports.tags = ["timelock"];
