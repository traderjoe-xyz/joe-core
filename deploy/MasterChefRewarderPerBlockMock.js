// Deploy for testing of MasterChefJoeV2
module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const sushi = await ethers.getContract("SushiToken");
  const mcv1 = await ethers.getContract("MasterChef");
  const mcv2 = await ethers.getContract("MasterChefJoeV2");
  const lpTokenAddress = "0xbf21027fbf3e6fff156e9f2464881898e4672713"; // WAVAX-USDT on Rinkeby

  const dummyToken = await deploy("ERC20Mock", {
    from: deployer,
    args: ["DummyToken", "DUMMY", "1"],
    log: true,
    deterministicDeployment: false
  });

  const rewarder = await deploy("MasterChefRewarderPerBlockMock", {
    from: deployer,
    args: [sushi.address, lpTokenAddress, 0, mcv1.address, mcv2.address]
    log: true,
    deterministicDeployment: false,
  });
  await (await mcv1.add("100", dummyToken.address, true)).wait();
  await (await dummyToken.approve(rewarder.address, "1")).wait();
  await (await rewarder.init(dummyToken.address)).wait();

};

module.exports.tags = ["MasterChefRewarderPerBlockMock"];
module.exports.dependencies = ["SushiToken", "MasterChef", "MasterChefJoeV2"];
