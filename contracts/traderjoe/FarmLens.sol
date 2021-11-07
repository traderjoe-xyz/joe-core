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

    function totalAllocPoint() external view returns (uint256);

    function joePerSec() external view returns (uint256);
}

contract FarmLens is BoringOwnable {
    using SafeMath for uint256;

    address public joe; // 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;
    address public wavax; // 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    IJoeFactory public joeFactory; // IJoeFactory(0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10);
    IMasterChef public chef; //0xd6a4F121CA35509aF06A0Be99093d08462f53052
    IMasterChef public chefv3; //0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00

    constructor(
        address joe_,
        address wavax_,
        IJoeFactory joeFactory_,
        IMasterChef chef_,
        IMasterChef chefv3_
    ) public {
        joe = joe_;
        wavax = wavax_;
        joeFactory = IJoeFactory(joeFactory_);
        chef = chef_;
        chefv3 = chefv3_;
    }

    function getAvaxPrice() public view returns (uint256) {
        uint256 priceFromWavaxUsdt = _getAvaxPrice(IJoePair(address(0xeD8CBD9F0cE3C6986b22002F03c6475CEb7a6256))); // 18
        uint256 priceFromWavaxUsdc = _getAvaxPrice(IJoePair(address(0x87Dee1cC9FFd464B79e058ba20387c1984aed86a))); // 18
        uint256 priceFromWavaxDai = _getAvaxPrice(IJoePair(address(0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1))); // 18

        uint256 sumPrice = priceFromWavaxUsdt.add(priceFromWavaxUsdc).add(priceFromWavaxDai); // 18
        uint256 avaxPrice = sumPrice / uint256(3); // 18
        return avaxPrice; // 18
    }

    function _getAvaxPrice(IJoePair pair) public view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        if (pair.token0() == wavax) {
            reserve1 = reserve1.mul(_tokenDecimalsMultiplier(pair.token1())); // 18
            return (reserve1.mul(uint256(1e18))) / reserve0; // 18
        } else {
            reserve0 = reserve0.mul(_tokenDecimalsMultiplier(pair.token0())); // 18
            return (reserve0.mul(uint256(1e18))) / reserve1; // 18
        }
    }

    function getPriceInUSD(address tokenAddress) public view returns (uint256) {
        return getAvaxPrice() / getPriceInAvax(tokenAddress); // 18
    }

    // Need to be aware of decimals here, not always 18, it depends on the token
    function getPriceInAvax(address tokenAddress) public view returns (uint256) {
        if (tokenAddress == wavax) {
            return uint256(1e18);
        }

        IJoePair pair = IJoePair(joeFactory.getPair(tokenAddress, wavax));

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        address token0Address = pair.token0();
        address token1Address = pair.token1();

        if (token0Address == wavax) {
            reserve1 = reserve1.mul(_tokenDecimalsMultiplier(token1Address)); // 18
            return (reserve1.mul(uint256(1e18))) / reserve0; // 18
        } else {
            reserve0 = reserve0.mul(_tokenDecimalsMultiplier(token0Address)); // 18
            return (reserve0.mul(uint256(1e18))) / reserve1; // 18
        }
    }

    function _tokenDecimalsMultiplier(address tokenAddress) public pure returns (uint256) {
        uint256 decimalsNeeded = 18 - IJoeERC20(tokenAddress).decimals();
        return uint256(1 * (10**decimalsNeeded));
    }

    function getReserveUSD(IJoePair pair) public view returns (uint256) {
        address token0Address = pair.token0();
        address token1Address = pair.token1();

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves(); // reserve0, reserve1 are 18 decimals

        uint256 token0PriceInAvax = getPriceInAvax(token0Address); // 18
        uint256 token1PriceInAvax = getPriceInAvax(token1Address); // 18
        uint256 token0ReserveUSD = (reserve0.mul(_tokenDecimalsMultiplier(token0Address))).mul(token0PriceInAvax).mul(
            getAvaxPrice()
        ); // 18.mul(18).mul(18) = 54 decimals
        uint256 token1ReserveUSD = (reserve1.mul(_tokenDecimalsMultiplier(token1Address))).mul(token1PriceInAvax).mul(
            getAvaxPrice()
        ); // 54

        uint256 reserveUSD = (token0ReserveUSD.add(token1ReserveUSD)) / uint256(1e36);

        return reserveUSD; // 18
    }

    struct FarmPair {
        address lpAddress;
        address token0Address;
        address token1Address;
        string token0Symbol;
        string token1Symbol;
        uint256 reserveUSD;
        uint256 totalSupply;
        address chefAddress;
        uint256 chefBalance;
        uint256 chefTotalAlloc;
        uint256 chefJoePerSec;
    }

    function getFarmPairs(address[] calldata pairAddresses, address chefAddress)
        public
        view
        returns (FarmPair[] memory)
    {
        FarmPair[] memory farmPairs = new FarmPair[](pairAddresses.length);

        for (uint256 i = 0; i < pairAddresses.length; i++) {
            // get pair information
            IJoePair lpToken = IJoePair(pairAddresses[i]);
            address lpAddress = address(lpToken);
            address token0Address = lpToken.token0();
            address token1Address = lpToken.token1();
            farmPairs[i].token0Address = token0Address;
            farmPairs[i].token1Address = token1Address;
            farmPairs[i].token0Symbol = IJoeERC20(token0Address).symbol();
            farmPairs[i].token1Symbol = IJoeERC20(token1Address).symbol();

            // calculate reserveUSD of lp
            farmPairs[i].reserveUSD = getReserveUSD(lpToken); // 18

            // calculate total supply of lp
            farmPairs[i].totalSupply = lpToken.totalSupply().mul(_tokenDecimalsMultiplier(lpAddress));

            // get masterChef data
            uint256 balance = lpToken.balanceOf(chefAddress);
            farmPairs[i].chefBalance = balance.mul(_tokenDecimalsMultiplier(lpAddress));
            farmPairs[i].chefAddress = chefAddress;
            farmPairs[i].chefTotalAlloc = IMasterChef(chefAddress).totalAllocPoint();
            farmPairs[i].chefJoePerSec = IMasterChef(chefAddress).joePerSec();
        }

        return farmPairs;
    }

    struct AllFarmData {
        uint256 avaxPriceUSD;
        uint256 joePriceUSD;
        uint256 totalAllocChef;
        uint256 totalAllocChefV3;
        uint256 joePerSecChef;
        uint256 joePerSecChefV3;
        FarmPair[] farmPairs;
        FarmPair[] farmPairsV3;
    }

    function getAllFarmData(address[] calldata pairAddresses) public view returns (AllFarmData memory) {
        AllFarmData memory allFarmData;

        allFarmData.avaxPriceUSD = getAvaxPrice();
        allFarmData.joePriceUSD = getPriceInUSD(joe);

        allFarmData.totalAllocChef = IMasterChef(chef).totalAllocPoint();
        allFarmData.joePerSecChef = IMasterChef(chef).joePerSec();

        allFarmData.totalAllocChefV3 = IMasterChef(chefv3).totalAllocPoint();
        allFarmData.joePerSecChefV3 = IMasterChef(chefv3).joePerSec();

        allFarmData.farmPairs = getFarmPairs(pairAddresses, address(chef));
        allFarmData.farmPairsV3 = getFarmPairs(pairAddresses, address(chefv3));

        return allFarmData;
    }
}
