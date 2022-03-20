module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  let joeAddress,
    wavaxAddress,
    wavaxUsdteAddress,
    wavaxUsdceAddress,
    wavaxUsdcAddress,
    joeFactoryAddress,
    chefAddressV2,
    chefAddressV3,
    boostedMasterChefAddress;

  if (chainId == "43114" || chainId == "31337") {
    joeAddress = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd";
    wavaxAddress = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7";
    wavaxUsdteAddress = "0xeD8CBD9F0cE3C6986b22002F03c6475CEb7a6256";
    wavaxUsdceAddress = "0xa389f9430876455c36478deea9769b7ca4e3ddb1";
    wavaxUsdcAddress = "0xf4003F4efBE8691B60249E6afbD307aBE7758adb";
    joeFactoryAddress = "0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10";
    chefAddressV2 = "0xd6a4F121CA35509aF06A0Be99093d08462f53052";
    chefAddressV3 = "0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00";
    boostedMasterChefAddress = "0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F";
  } else if (chainId === "4") {
    joeAddress = "0xce347E069B68C53A9ED5e7DA5952529cAF8ACCd4";
    wavaxAddress = "0xc778417E063141139Fce010982780140Aa0cD5Ab";
    wavaxUsdteAddress = "0x63Fce17ba68c82A322fDd5a4D03AedBEdBD730fD";
    wavaxUsdceAddress = "0x63Fce17ba68c82A322fDd5a4D03AedBEdBD730fD";
    wavaxUsdcAddress = "0x63Fce17ba68c82A322fDd5a4D03AedBEdBD730fD";
    joeFactoryAddress = "0x86f83be9770894d8e46301b12E88e14AdC6cdb5F";
    chefAddressV2 = "0x1F51b7697A1919cF301845c93D4843FD620ad7Cc";
    chefAddressV3 = "0xEedf119022F1Bb5F63676BbE855c82151B7198AF";
    boostedMasterChefAddress = "0x460d978831afd5Af99738E060C3ad8a76e592beA";
  }

  const contract = await deploy("FarmLensV2", {
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
      boostedMasterChefAddress,
    ],
    log: true,
  });
};

module.exports.tags = ["FarmLensV2"];
module.exports.dependencies = [];
