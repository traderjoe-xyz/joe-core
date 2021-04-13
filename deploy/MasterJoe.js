module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments

  const { deployer, dev } = await getNamedAccounts()

  const joe = await ethers.getContract("JoeToken")
  
  const { address } = await deploy("MasterJoe", {
    from: deployer,
    args: [joe.address, dev, "1000000000000000000000", "0", "1000000000000000000000"],
    log: true,
    deterministicDeployment: false
  })

  if (await joe.owner() !== address) {
    // Transfer Joe Ownership to Joe
    console.log("Transfer Joe Ownership to Joe")
    await (await joe.transferOwnership(address)).wait()
  }

  const masterJoe = await ethers.getContract("MasterJoe")
  if (await masterJoe.owner() !== dev) {
    // Transfer ownership of MasterJoe to dev
    console.log("Transfer ownership of MasterJoe to dev")
    await (await masterJoe.transferOwnership(dev)).wait()
  }
}

module.exports.tags = ["MasterJoe"]
module.exports.dependencies = ["JoeFactory", "JoeRouter02", "JoeToken"]
