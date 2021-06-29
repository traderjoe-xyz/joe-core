const PANGOLIN_ROUTER = new Map();
PANGOLIN_ROUTER.set("1", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
PANGOLIN_ROUTER.set("3", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
PANGOLIN_ROUTER.set("4", "0x62387711313CC10F433B32E010A05Bf768c2F037");
PANGOLIN_ROUTER.set("5", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
PANGOLIN_ROUTER.set("42", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D");
PANGOLIN_ROUTER.set("1287", "0x2823caf546C7d09a4832bd1da14f2C6b6E665e05");
PANGOLIN_ROUTER.set("43113", "0x2D99ABD9008Dc933ff5c0CD271B88309593aB921");
PANGOLIN_ROUTER.set("43114", "0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106");
PANGOLIN_ROUTER.set(
  "79377087078960",
  "0x0B72c0193CD598b536210299d358A5b720A262b8"
);

module.exports = async function ({
  getNamedAccounts,
  getChainId,
  deployments,
}) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  if (!PANGOLIN_ROUTER.has(chainId)) {
    throw Error("No Pangolin Router");
  }

  const pangolinRouterAddress = PANGOLIN_ROUTER.get(chainId);

  const joeRouterAddress = (await deployments.get("JoeRouter02")).address;

  await deploy("JoeRoll", {
    from: deployer,
    args: [pangolinRouterAddress, joeRouterAddress],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["JoeRoll"];
module.exports.dependencies = ["JoeRouter02"];
