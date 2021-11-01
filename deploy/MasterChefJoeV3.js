module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;

  const { deployer, dev, treasury, investor } = await getNamedAccounts();

  const PID = 66;

  await deploy("ERC20Mock", {
    from: deployer,
    args: ["Joe Dummy Token", "DUMMY", "1"],
    log: true,
    deterministicDeployment: false,
  });
  const dummyToken = await ethers.getContract("ERC20Mock");
  await dummyToken.renounceOwnership();
  const joe = await ethers.getContract("JoeToken");
  const MCV2 = await ethers.getContract("MasterChefJoeV2");

  const { address } = await deploy("MasterChefJoeV3", {
    from: deployer,
    args: [MCV2.address, joe.address, PID],
    log: true,
    deterministicDeployment: false,
  });
  const MCV3 = await ethers.getContract("MasterChefJoeV3");

  await (await MCV2.add(100, dummyToken.address, false)).wait();
  await (await dummyToken.approve(MCV3.address, PID)).wait();
  await rewarder.init(dummyToken.address, {
    gasLimit: 245000,
  });
};

module.exports.tags = ["MasterChefJoeV3"];
module.exports.dependencies = ["JoeFactory", "JoeRouter02", "JoeToken"];
