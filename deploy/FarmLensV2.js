const { WAVAX } = require("@traderjoe-xyz/sdk");

module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  let wavaxAddress;
  let wavaxUsdteAddress;
  let wavaxUsdceAddress;
  let wavaxUsdcAddress;

  if (chainId === "31337") {
    wavaxAddress = (await deployments.get("WAVAX9Mock")).address;
  } else if (chainId in WAVAX) {
    wavaxAddress = WAVAX[chainId].address;
  } else {
    throw Error("No WAVAX!");
  }
  if (chainId === "43114") {
    wavaxUsdteAddress = address("0xeD8CBD9F0cE3C6986b22002F03c6475CEb7a6256");
    wavaxUsdceAddress = address("0xa389f9430876455c36478deea9769b7ca4e3ddb1");
    wavaxUsdcAddress = address("0xf4003F4efBE8691B60249E6afbD307aBE7758adb");
  } else if (chainId === "4") {
    wavaxUsdteAddress = address("0x63fce17ba68c82a322fdd5a4d03aedbedbd730fd");
    wavaxUsdceAddress = address("0x63fce17ba68c82a322fdd5a4d03aedbedbd730fd");
    wavaxUsdcAddress = address("0x63fce17ba68c82a322fdd5a4d03aedbedbd730fd");
  }

  const joeAddress = (await deployments.get("JoeToken")).address;
  const joeFactoryAddress = (await deployments.get("JoeFactory")).address;
  const chefAddressV2 = (await deployments.get("MasterChefJoeV2")).address;
  const chefAddressV3 = (await deployments.get("MasterChefJoeV3")).address;

  await deploy("FarmLensV2", {
    from: deployer,
    args: [
      joeAddress,
      wavaxAddress,
      wavaxUsdteAddress,
      wavaxUsdceAddress,
      wavaxUsdcAddress,
      joeFactoryAddress,
      chefAddressV2,
      chefAddressV3,
    ],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["FarmLensV2"];
module.exports.dependencies = [];
