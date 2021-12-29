const { WAVAX } = require("@traderjoe-xyz/sdk");

module.exports = async function ({ ethers, getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  const factory = await ethers.getContract("JoeFactory");
  const bar = await ethers.getContract("JoeBar");
  const joe = await ethers.getContract("JoeToken");

  let wavaxAddress;

  if (chainId === "31337") {
    wavaxAddress = (await deployments.get("WAVAX9Mock")).address;
  } else if (chainId in WAVAX) {
    wavaxAddress = WAVAX[chainId].address;
  } else {
    throw Error("No WAVAX!");
  }

  await deploy("JoeMakerV3", {
    from: deployer,
    args: [factory.address, bar.address, joe.address, wavaxAddress],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["JoeMakerV3"];
module.exports.dependencies = [
  "JoeFactory",
  "JoeRouter02",
  "JoeBar",
  "JoeToken",
];
