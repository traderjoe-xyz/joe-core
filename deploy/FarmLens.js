const { WAVAX } = require("@traderjoe-xyz/sdk");

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

  const joeAddress = (await deployments.get("JoeToken")).address;
  const joeFactoryAddress = (await deployments.get("JoeFactory")).address;
  const chefAddress = (await deployments.get("MasterChefJoeV2")).address;
  const chefAddressV3 = (await deployments.get("MasterChefJoeV3")).address;

  await deploy("FarmLens", {
    from: deployer,
    args: [
      joeAddress,
      wavaxAddress,
      joeFactoryAddress,
      chefAddress,
      chefAddressV3
    ],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["FarmLens"];
module.exports.dependencies = ["JoeToken", "JoeFactory", "MasterChefJoeV2", "MasterChefJoeV3", "WAVAX9Mock"];
