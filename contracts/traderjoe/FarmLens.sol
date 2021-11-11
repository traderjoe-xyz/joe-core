// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "../libraries/SafeMath.sol";
import "../libraries/SafeERC20.sol";

import "../interfaces/IERC20.sol";
import "./interfaces/IJoeERC20.sol";
import "./interfaces/IJoePair.sol";
import "./interfaces/IJoeFactory.sol";

import "../boringcrypto/BoringOwnable.sol";

interface IMasterChef {
    struct PoolInfo {
        IJoeERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. JOE to distribute per block.
        uint256 lastRewardTimestamp; // Last block number that JOE distribution occurs.
        uint256 accJoePerShare; // Accumulated JOE per share, times 1e12. See below.
    }

    function poolLength() external view returns (uint256);

    function poolInfo(uint256 pid) external view returns (IMasterChef.PoolInfo memory);

    function totalAllocPoint() external view returns (uint256);

    function joePerSec() external view returns (uint256);
}

contract FarmLens is BoringOwnable {
    using SafeMath for uint256;

    address public joe; // 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;
    address public wavax; // 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    IJoeFactory public joeFactory; // IJoeFactory(0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10);
    IMasterChef public chefv2; //0xd6a4F121CA35509aF06A0Be99093d08462f53052
    IMasterChef public chefv3; //0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00

    constructor(
        address joe_,
        address wavax_,
        IJoeFactory joeFactory_,
        IMasterChef chefv2_,
        IMasterChef chefv3_
    ) public {
        joe = joe_;
        wavax = wavax_;
        joeFactory = IJoeFactory(joeFactory_);
        chefv2 = chefv2_;
        chefv3 = chefv3_;
    }

    /// @notice Returns price of avax in usd.
    function getAvaxPrice() public view returns (uint256) {
        uint256 priceFromWavaxUsdt = _getAvaxPrice(IJoePair(address(0xeD8CBD9F0cE3C6986b22002F03c6475CEb7a6256))); // 18
        uint256 priceFromWavaxUsdc = _getAvaxPrice(IJoePair(address(0x87Dee1cC9FFd464B79e058ba20387c1984aed86a))); // 18
        uint256 priceFromWavaxDai = _getAvaxPrice(IJoePair(address(0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1))); // 18

        uint256 sumPrice = priceFromWavaxUsdt.add(priceFromWavaxUsdc).add(priceFromWavaxDai); // 18
        uint256 avaxPrice = sumPrice / 3; // 18
        return avaxPrice; // 18
    }

    /// @notice Returns value of wavax in units of stablecoins per wavax.
    /// @param pair A wavax-stablecoin pair.
    function _getAvaxPrice(IJoePair pair) private view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        if (pair.token0() == wavax) {
            reserve1 = reserve1.mul(_tokenDecimalsMultiplier(pair.token1())); // 18
            return (reserve1.mul(1e18)) / reserve0; // 18
        } else {
            reserve0 = reserve0.mul(_tokenDecimalsMultiplier(pair.token0())); // 18
            return (reserve0.mul(1e18)) / reserve1; // 18
        }
    }

    /// @notice Get the price of a token in Usd.
    /// @param tokenAddress Address of the token.
    function getPriceInUsd(address tokenAddress) public view returns (uint256) {
        return (getAvaxPrice().mul(getPriceInAvax(tokenAddress))) / 1e18; // 18
    }

    /// @notice Get the price of a token in Avax.
    /// @param tokenAddress Address of the token.
    /// @dev Need to be aware of decimals here, not always 18, it depends on the token.
    function getPriceInAvax(address tokenAddress) public view returns (uint256) {
        if (tokenAddress == wavax) {
            return 1e18;
        }

        IJoePair pair = IJoePair(joeFactory.getPair(tokenAddress, wavax));

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        address token0Address = pair.token0();
        address token1Address = pair.token1();

        if (token0Address == wavax) {
            reserve1 = reserve1.mul(_tokenDecimalsMultiplier(token1Address)); // 18
            return (reserve0.mul(1e18)) / reserve1; // 18
        } else {
            reserve0 = reserve0.mul(_tokenDecimalsMultiplier(token0Address)); // 18
            return (reserve1.mul(1e18)) / reserve0; // 18
        }
    }

    /// @notice Calculates the multiplier needed to scale a token's numerical field to 18 decimals.
    /// @param tokenAddress Address of the token.
    function _tokenDecimalsMultiplier(address tokenAddress) private pure returns (uint256) {
        uint256 decimalsNeeded = 18 - IJoeERC20(tokenAddress).decimals();
        return 1 * (10**decimalsNeeded);
    }

    /// @notice Calculates the reserve of a pair in usd.
    /// @param pair Pair for which the reserve will be calculated.
    function getReserveUsd(IJoePair pair) public view returns (uint256) {
        address token0Address = pair.token0();
        address token1Address = pair.token1();

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        reserve0 = reserve0.mul(_tokenDecimalsMultiplier(token0Address)); // 18
        reserve1 = reserve1.mul(_tokenDecimalsMultiplier(token1Address)); // 18

        uint256 token0PriceInAvax = getPriceInAvax(token0Address); // 18
        uint256 token1PriceInAvax = getPriceInAvax(token1Address); // 18
        uint256 reserve0Avax = reserve0.mul(token0PriceInAvax); // 36;
        uint256 reserve1Avax = reserve1.mul(token1PriceInAvax); // 36;
        uint256 reserveAvax = (reserve0Avax.add(reserve1Avax)) / 1e18; // 18
        uint256 reserveUsd = (reserveAvax.mul(getAvaxPrice())) / 1e18; // 18

        return reserveUsd; // 18
    }

    struct FarmPair {
        address lpAddress;
        address token0Address;
        address token1Address;
        string token0Symbol;
        string token1Symbol;
        uint256 reserveUsd;
        uint256 totalSupplyScaled;
        address chefAddress;
        uint256 chefBalanceScaled;
        uint256 chefTotalAlloc;
        uint256 chefJoePerSec;
    }

    /// @notice Gets the farm pair data for a given MasterChef.
    /// @param chefAddress The address of the MasterChef.
    /// @param blacklistedPids Array of all ids of pools that are blacklisted from our farms.
    function getFarmPairs(address chefAddress, uint256[] calldata blacklistedPids)
        public
        view
        returns (FarmPair[] memory)
    {
        IMasterChef chef = IMasterChef(chefAddress);
        uint256 poolsLength = chef.poolLength();

        FarmPair[] memory farmPairs = new FarmPair[](poolsLength - blacklistedPids.length);
        uint256 farmPairsIndex = 0;

        for (uint256 i = 0; i < poolsLength; i++) {
            if (_pidInBlacklist(i, blacklistedPids)) {
                continue;
            }

            IMasterChef.PoolInfo memory pool = chef.poolInfo(i);
            IJoePair lpToken = IJoePair(address(pool.lpToken));

            // get pair information
            PairDataForFarm memory pair = _getPairData(lpToken);
            farmPairs[farmPairsIndex].lpAddress = pair.lpAddress;
            farmPairs[farmPairsIndex].token0Address = pair.token0Address;
            farmPairs[farmPairsIndex].token1Address = pair.token1Address;
            farmPairs[farmPairsIndex].token0Symbol = pair.token0Symbol;
            farmPairs[farmPairsIndex].token1Symbol = pair.token1Symbol;

            // calculate reserveUsd of lp
            farmPairs[farmPairsIndex].reserveUsd = getReserveUsd(lpToken); // 18

            // calculate total supply of lp
            farmPairs[farmPairsIndex].totalSupplyScaled = lpToken.totalSupply().mul(_tokenDecimalsMultiplier(pair.lpAddress));

            // get masterChef data
            farmPairs[farmPairsIndex].chefBalanceScaled = lpToken.balanceOf(chefAddress).mul(_tokenDecimalsMultiplier(pair.lpAddress));
            farmPairs[farmPairsIndex].chefAddress = chefAddress;
            farmPairs[farmPairsIndex].chefTotalAlloc = chef.totalAllocPoint();
            farmPairs[farmPairsIndex].chefJoePerSec = chef.joePerSec();
            farmPairsIndex++;
        }

        return farmPairs;
    }

    struct PairDataForFarm {
        address lpAddress;
        address token0Address;
        address token1Address;
        string token0Symbol;
        string token1Symbol;
    }

    /// @notice Retrieves the pair data for a given lp token
    /// @param lpToken The lp token to get pair data for
    /// @dev This logic is seperated out to avoid a call stack error from having too many local variables in getFarmPairs()
    function _getPairData(IJoePair lpToken) private view returns (PairDataForFarm memory) {
        PairDataForFarm memory pair;

        address lpAddress = address(lpToken);
        address token0Address = lpToken.token0();
        address token1Address = lpToken.token1();
        pair.lpAddress = lpAddress;
        pair.token0Address = token0Address;
        pair.token1Address = token1Address;
        pair.token0Symbol = IJoeERC20(token0Address).symbol();
        pair.token1Symbol = IJoeERC20(token1Address).symbol();

        return pair;
    }

    function _pidInBlacklist(uint256 pid, uint256[] calldata blacklistedPids) private view returns (bool) {
        for (uint256 i = 0; i < blacklistedPids.length; i++) {
            if (blacklistedPids[i] == pid) {
                return true;
            }
        }

        return false;
    }

    struct AllFarmData {
        uint256 avaxPriceUsd;
        uint256 joePriceUsd;
        uint256 totalAllocChefV2;
        uint256 totalAllocChefV3;
        uint256 joePerSecChefV2;
        uint256 joePerSecChefV3;
        FarmPair[] farmPairsV2;
        FarmPair[] farmPairsV3;
    }

    /// @notice Get all data needed for farm pages on interface.
    /// @param blacklistedPids Array of all ids of pools that are blacklisted from our farms.
    function getAllFarmData(uint256[] calldata blacklistedPids) public view returns (AllFarmData memory) {
        AllFarmData memory allFarmData;

        allFarmData.avaxPriceUsd = getAvaxPrice();
        allFarmData.joePriceUsd = getPriceInUsd(joe);

        allFarmData.totalAllocChefV2 = IMasterChef(chefv2).totalAllocPoint();
        allFarmData.joePerSecChefV2 = IMasterChef(chefv2).joePerSec();

        allFarmData.totalAllocChefV3 = IMasterChef(chefv3).totalAllocPoint();
        allFarmData.joePerSecChefV3 = IMasterChef(chefv3).joePerSec();

        allFarmData.farmPairsV2 = getFarmPairs(address(chefv2), blacklistedPids);
        allFarmData.farmPairsV3 = getFarmPairs(address(chefv3), blacklistedPids);

        return allFarmData;
    }
}
