const JOE_AVAX_LP = new Map();
JOE_AVAX_LP.set("4", "0xab9ba8c7e7b00381027061a8506d895e8938060b");

module.exports = async function ({ ethers, getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  if (!JOE_AVAX_LP.has(chainId)) {
    throw Error("No JOE-AVAX LP");
  }

  const joeAvaxLpAddress = JOE_AVAX_LP.get(chainId);
  const bar = await ethers.getContract("JoeBar");
  const joe = await ethers.getContract("JoeToken");
  const chef = await ethers.getContract("MasterChefJoeV2");
  const pid = 0;

  await deploy("JoeVote", {
    from: deployer,
    args: [joeAvaxLpAddress, bar.address, joe.address, chef.address, pid],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["JoeVote"];
module.exports.dependencies = ["JoeBar", "JoeToken", "MasterChefJoeV2"];
