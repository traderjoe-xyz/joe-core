module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy, catchUnknownSigner } = deployments;
  const { deployer } = await getNamedAccounts();

  let PID,
    joeAddress,
    veJoeAddress = (await deployments.get("VeJoeToken")).address,
    dummyTokenAddress = (await deployments.get("BoostedMasterChefToken"))
      .address,
    masterChefV2Address,
    proxyOwner,
    bmcj;

  const chainId = await getChainId();
  if (chainId == 4) {
    // rinkeby contract addresses
    joeAddress = "0xce347E069B68C53A9ED5e7DA5952529cAF8ACCd4";
    masterChefV2Address = "0x1F51b7697A1919cF301845c93D4843FD620ad7Cc";
    PID = 10;
    proxyOwner = deployer.address;
  } else if (chainId == 43114 || chainId == 31337) {
    // avalanche mainnet or hardhat network addresses
    joeAddress = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd";
    masterChefV2Address = "0xd6a4F121CA35509aF06A0Be99093d08462f53052";
    PID = 69;
    proxyOwner = "0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2";
  }

  await catchUnknownSigner(async () => {
    bmcj = await deploy("BoostedMasterChefJoe", {
      from: deployer,
      proxy: {
        owner: proxyOwner,
        proxyContract: "OpenZeppelinTransparentProxy",
        viaAdminContract: "DefaultProxyAdmin",
        execute: {
          init: {
            methodName: "initialize",
            args: [masterChefV2Address, joeAddress, veJoeAddress, PID],
          },
        },
      },
      log: true,
    });
  });
};

module.exports.tags = ["BoostedMasterChefJoe"];
module.exports.dependencies = ["BoostedMasterChefToken", "VeJoeToken"];
