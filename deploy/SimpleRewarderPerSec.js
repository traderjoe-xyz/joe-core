// Deploy for testing of MasterChefJoeV2
module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const sushi = await ethers.getContract("SushiToken");
  // const mcv2 = await ethers.getContract("MasterChefJoeV2");
  const lpTokenAddress = "0x6d551ad3570888d49da4d6c8b8a626c8cbfd5ac2"; // WAVAX-USDT on Rinkeby
  const mcv2Address = "0xff6eA1C23107e0D835930612ee2F4Cd975331D0D";

  await deploy("SimpleRewarderPerSec", {
    from: deployer,
    args: [
      sushi.address,
      lpTokenAddress,
      "100000000000000000000", // 100 SUSHI per sec
      mcv2Address,
    ],
    gasLmit: 22000000000,
    log: true,
    deterministicDeployment: false,
  });
  const rewarder = await ethers.getContract("SimpleRewarderPerSec");

  console.log("Minting 10M Sushi to rewarder...");
  await sushi.mint(rewarder.address, "10000000000000000000000000");
};

module.exports.tags = ["SimpleRewarderPerSec"];
module.exports.dependencies = ["SushiToken"];
