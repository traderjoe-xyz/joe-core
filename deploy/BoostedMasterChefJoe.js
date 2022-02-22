module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  let PID,
    joeAddress,
    veJoeAddress = (await deployments.get("VeJoeToken")).address,
    masterChefV2Address;

  const DummyToken = await deploy("ERC20Mock", {
    from: deployer,
    args: ["Joe Boost Dummy Token", "BDUMMY", "1"],
    log: true,
  });

  const dummyToken = await ethers.getContract("ERC20Mock", DummyToken.address);
  await dummyToken.renounceOwnership();

  if (chainId == 4) {
    // rinkeby contract addresses
    joeAddress = "0xce347E069B68C53A9ED5e7DA5952529cAF8ACCd4";
    masterChefV2Address = "0x1F51b7697A1919cF301845c93D4843FD620ad7Cc";
  } else if (chainId == 43114 || chainId == 31337) {
    // avalanche mainnet or hardhat network addresses
    joeAddress = "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd";
    masterChefV2Address = "0xC98C3C547DDbcc0029F38E0383C645C202aD663d";
  }

  const MCV2 = await ethers.getContract("MasterChefJoeV2", masterChefV2Address);
  await (await MCV2.add(100, dummyToken.address, false)).wait();

  // PID should be the last added pool.
  PID = await MCV2.poolLength;

  const { address } = await deploy("BoostedMasterChefJoe", {
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

  const boostedMasterChef = await ethers.getContract(
    "BoostedMasterChefJoe",
    address
  );
  await (await dummyToken.approve(boostedMasterChef.address, 1)).wait();
  await (await BoostedMasterChefJoe.init(dummyToken.address)).wait();
};

module.exports.tags = ["BoostedMasterChefJoe"];
module.exports.dependencies = ["VeJoeToken"];
