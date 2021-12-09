const { WAVAX } = require("@traderjoe-xyz/sdk");

module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  let wavaxAddress;
  let wavaxUsdtAddress;
  let wavaxUsdcAddress;
  let wavaxDaiAddress;

  if (chainId === "31337") {
    wavaxAddress = (await deployments.get("WAVAX9Mock")).address;
  } else if (chainId in WAVAX) {
    wavaxAddress = WAVAX[chainId].address;
  } else {
    throw Error("No WAVAX!");
  }
  if (chainId === "43114") {  
    wavaxUsdtAddress = address("0xeD8CBD9F0cE3C6986b22002F03c6475CEb7a6256");
    wavaxUsdcAddress = address("0x87Dee1cC9FFd464B79e058ba20387c1984aed86a");
    wavaxDaiAddress = address("0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1");
  } else if (chainId === "4") {
    wavaxUsdtAddress = address("0x63fce17ba68c82a322fdd5a4d03aedbedbd730fd");
    wavaxUsdcAddress = address("0x63fce17ba68c82a322fdd5a4d03aedbedbd730fd");
    wavaxDaiAddress = address("0x63fce17ba68c82a322fdd5a4d03aedbedbd730fd");
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
      wavaxUsdtAddress,
      wavaxUsdcAddress,
      wavaxDaiAddress,
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
