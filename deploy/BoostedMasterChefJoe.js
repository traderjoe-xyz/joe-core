module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  let PID,
    joeAddress,
    veJoeAddress = (await deployments.get("VeJoeToken")).address,
    dummyTokenAddress = (await deployments.get("BoostedMasterChefToken"))
      .address,
    masterChefV2Address;

  const chainId = await getChainId();
  if (chainId == 4) {
    // rinkeby contract addresses
    joeAddress = "0xce347E069B68C53A9ED5e7DA5952529cAF8ACCd4";
    masterChefV2Address = "0x1F51b7697A1919cF301845c93D4843FD620ad7Cc";
    PID = 8;
  } else if (chainId == 43114 || chainId == 31337) {
    // avalanche mainnet or hardhat network addresses
    joeAddress = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd";
    masterChefV2Address = "0xd6a4F121CA35509aF06A0Be99093d08462f53052";
    /// XXX Pid needs to be pre-created.
    PID = 0;
  }

  const bmcj = await deploy("BoostedMasterChefJoe", {
    from: deployer,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [masterChefV2Address, joeAddress, veJoeAddress, PID],
        },
      },
    },
    log: true,
  });
  if (bmcj.newlyDeployed) {
    const dummyToken = await ethers.getContractAt("ERC20Mock", dummyTokenAddress);
    const boostedMasterChefJoe = await ethers.getContractAt(
      "BoostedMasterChefJoe",
      bmcj.address
    );
    await dummyToken.approve(boostedMasterChefJoe.address, 1);
    await boostedMasterChefJoe.init(dummyToken.address);
  }
};

module.exports.tags = ["BoostedMasterChefJoe"];
module.exports.dependencies = ["BoostedMasterChefToken", "VeJoeToken"];
