module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy, catchUnknownSigner } = deployments;
  const { deployer } = await getNamedAccounts();

  let joeAddress,
    veJoeAddress = (await deployments.get("VeJoeToken")).address,
    veJoePerSharePerSec = 3170979198376,
    speedUpVeJoePerSharePerSec = 3170979198376,
    speedUpThreshold = 5,
    speedUpDuration = 15 * 60 * 60 * 24,
    maxCapPct = 10000,
    proxyOwner;

  const chainId = await getChainId();
  if (chainId == 4) {
    // rinkeby contract addresses
    joeAddress = ethers.utils.getAddress(
      "0xce347E069B68C53A9ED5e7DA5952529cAF8ACCd4"
    );
    proxyOwner = deployer.address;
  } else if (chainId == 43114 || chainId == 31337) {
    // avalanche mainnet or hardhat network addresses
    joeAddress = ethers.utils.getAddress(
      "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd"
    );
    // multisig
    proxyOwner = "0x2fbB61a10B96254900C03F1644E9e1d2f5E76DD2";
  }

  await catchUnknownSigner(
    deploy("VeJoeStaking", {
      from: deployer,
      proxy: {
        owner: proxyOwner,
        proxyContract: "OpenZeppelinTransparentProxy",
        viaAdminContract: "DefaultProxyAdmin",
        execute: {
          init: {
            methodName: "initialize",
            args: [
              joeAddress,
              veJoeAddress,
              veJoePerSharePerSec,
              speedUpVeJoePerSharePerSec,
              speedUpThreshold,
              speedUpDuration,
              maxCapPct,
            ],
          },
        },
      },
      log: true,
    })
  );
};

module.exports.tags = ["VeJoeStaking"];
module.exports.dependencies = ["VeJoeToken"];
