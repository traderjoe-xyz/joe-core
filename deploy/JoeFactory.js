// Defining bytecode and abi from original contract on mainnet to ensure bytecode matches and it produces the same pair code hash
// const { bytecode, abi } = require('../deployments/fuji/JoeFactory.json')

module.exports = async function ({
  ethers,
  getNamedAccounts,
  deployments,
  getChainId,
}) {
  const { deploy } = deployments;

  const { deployer, dev } = await getNamedAccounts();

  await deploy("JoeFactory", {
    // contract: {
    //   abi,
    //   bytecode,
    // },
    from: deployer,
    args: [dev],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["JoeFactory", "AMM"];
