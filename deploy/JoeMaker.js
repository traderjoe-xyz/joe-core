const { WAVAX } = require("@pangolindex/sdk");

module.exports = async function ({
  ethers: { getNamedSigner },
  getNamedAccounts,
  deployments,
}) {
  const { deploy } = deployments;

  const { deployer, dev } = await getNamedAccounts();

  const chainId = await getChainId();

  const factory = await ethers.getContract("JoeFactory");
  const bar = await ethers.getContract("JoeBar");
  const joe = await ethers.getContract("JoeToken");

  let wavaxAddress;

  if (chainId === "31337") {
    wavaxAddress = (await deployments.get("WAVAX9Mock")).address;
  } else if (chainId in WAVAX) {
    wavaxAddress = WAVAX[chainId].address;
  } else if (chainId === "3") {
    wavaxAddress = "0xc778417E063141139Fce010982780140Aa0cD5Ab"; // ropsten
  } else if (chainId === "4") {
    wavaxAddress = "0xc778417E063141139Fce010982780140Aa0cD5Ab"; // rinkeby
  } else {
    throw Error("No WAVAX!");
  }

  await deploy("JoeMaker", {
    from: deployer,
    args: [factory.address, bar.address, joe.address, wavaxAddress],
    log: true,
    deterministicDeployment: false,
  });

  const maker = await ethers.getContract("JoeMaker");
  if ((await maker.owner()) !== dev) {
    console.log("Setting maker owner");
    await (await maker.transferOwnership(dev, true, false)).wait();
  }
};

module.exports.tags = ["JoeMaker"];
module.exports.dependencies = [
  "JoeFactory",
  "JoeRouter02",
  "JoeBar",
  "JoeToken",
];
