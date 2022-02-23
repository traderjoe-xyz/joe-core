module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  let factoryAddress, stakingAddress, rewardTokenAddress, wavaxAddress;

  const chainId = await getChainId();
  if (chainId == 4) {
    // rinkeby contract addresses
    factoryAddress = "0x86f83be9770894d8e46301b12E88e14AdC6cdb5F";
    rewardTokenAddress = "0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10";
    wavaxAddress = "0xc778417e063141139fce010982780140aa0cd5ab"; // WETH
  } else if (chainId == 43114 || chainId == 31337) {
    // avalanche mainnet or hardhat network addresses
    factoryAddress = "0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10";
    rewardTokenAddress = "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E";
    wavaxAddress = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7";
  }

  stakingAddress = (await deployments.get("StableJoeStaking")).address;

  await deploy("MoneyMaker", {
    from: deployer,
    args: [factoryAddress, stakingAddress, rewardTokenAddress, wavaxAddress],
    log: true,
  });
};
module.exports.tags = ["MoneyMaker"];
module.exports.dependencies = ["StableJoeStaking"];
