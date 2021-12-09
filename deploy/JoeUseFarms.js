const { WAVAX } = require("@traderjoe-xyz/sdk");

module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  let wavaxAddress;
  let usdtAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
  let usdcAddress = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
  let daiAddress = "0x6b175474e89094c44da98b954eedeac495271d0f";

  if (chainId === "31337") {
    wavaxAddress = (await deployments.get("WAVAX9Mock")).address;
  } else if (chainId in WAVAX) {
    wavaxAddress = WAVAX[chainId].address;
  } else {
    throw Error("No WAVAX!");
  }

  const pangolinFactoryAddress = {
    4: "0xE2eCc226Fd2D5CEad96F3f9f00eFaE9fAfe75eB8",
    43113: "0xc79A395cE054B9F3B73b82C4084417CA9291BC87",
    43114: "0xefa94DE7a4656D787667C749f7E1223D71E9FD88",
    31337: wavaxAddress,
  };

  const joeAddress = (await deployments.get("JoeToken")).address;
  const joeFactoryAddress = (await deployments.get("JoeFactory")).address;

  await deploy("JoeUseFarms", {
    from: deployer,
    args: [
      joeAddress,
      wavaxAddress,
      usdtAddress,
      usdcAddress,
      daiAddress,
      joeFactoryAddress,
      chefAddress,
      chefAddressV3,
    ],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["FarmLens"];
module.exports.dependencies = [
  "JoeToken",
  "JoeFactory",
  "MasterChefJoeV2",
  "MasterChefJoeV3",
  "WAVAX9Mock",
];
