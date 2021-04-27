const { WAVAX } = require("@joe-defi/sdk");

module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  let wavaxAddress;

  if (chainId === "31337") {
    wavaxAddress = (await deployments.get("WAVAX9Mock")).address;
  } else if (chainId in WAVAX) {
    wavaxAddress = WAVAX[chainId].address;
  } else {
    throw Error("No WAVAX!");
  }

  const pangolinFactoryAddress = {
    4: "0x5Aac695d3a63139ae64817049Df9230a82473f4B",
    43113: "0xc79A395cE054B9F3B73b82C4084417CA9291BC87",
    43114: "0xefa94DE7a4656D787667C749f7E1223D71E9FD88",
  };

  const chefAddress = (await deployments.get("MasterChefJoe")).address;
  const joeFactoryAddress = (await deployments.get("JoeFactory")).address;

  await deploy("BoringCryptoDashboardV2", {
    from: deployer,
    args: [
      chefAddress,
      pangolinFactoryAddress[chainId],
      joeFactoryAddress,
      wavaxAddress,
    ],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["BoringCryptoDashboardV2"];
module.exports.dependencies = ["MasterChefJoe", "JoeFactory"];
