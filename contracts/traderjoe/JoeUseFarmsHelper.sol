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

    function poolInfo(uint256 pid) external view returns (IMasterChef.PoolInfo memory);
    function poolLength() external view returns (uint256);
    function totalAllocPoint() external view returns (uint256);
}

contract JoeUseFarmsHelper is BoringOwnable {
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

    // MAIN FUNCTIONS FOR GETTING AVAX PRICE
    function getAvaxPrice() public view returns (uint256) {
        uint256 priceFromWavaxUsdt = _getAvaxPrice(IJoePair(address(0xeD8CBD9F0cE3C6986b22002F03c6475CEb7a6256))).mul(uint256(1e12)); // 18
        uint256 priceFromWavaxUsdc = _getAvaxPrice(IJoePair(address(0x87Dee1cC9FFd464B79e058ba20387c1984aed86a))); // 18
        uint256 priceFromWavaxDai = _getAvaxPrice(IJoePair(address(0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1))).mul(uint256(1e12)); // 18

        uint256 sumPrice = priceFromWavaxUsdt.add(priceFromWavaxUsdc).add(priceFromWavaxDai); // 18
        uint256 avaxPrice = sumPrice / uint256(3); // 18
        return avaxPrice; // 18
    }

    function _getAvaxPrice(IJoePair pair) public view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        if (pair.token0() == wavax) {
            return (reserve1.mul(uint256(1e18))) / reserve0; // 18
        } else {
            return (reserve0.mul(uint256(1e18))) / reserve1; // 18
        }
    }

    function getPriceInUSD(address tokenAddress) public view returns (uint256) {
        return getAvaxPrice().mul(getPriceInAvax(tokenAddress)) / uint256(1e18); // 36 / 18 = 1
    }

    function retrieveDecimalsPair(address pairAddress) public view returns (uint8) {
        IJoePair pair = IJoePair(pairAddress);
        return pair.decimals();
    }

    function retrieveDecimalsToken(address tokenAddress) public view returns (uint8) {
        IJoeERC20 token = IJoeERC20(tokenAddress);
        return token.decimals();
    }

    function testAdd(uint256 price1, uint256 price2) public view returns (uint256) {
        return price1.add(price2);
    }

    function testDivide(uint256 numerator, uint256 denominator) public view returns (uint256) {
        return numerator / denominator;
    }

    // Need to be aware of decimals here, not always 18, it depends on the token
    function getPriceInAvax(address tokenAddress) public view returns (uint256) {
        if (tokenAddress == wavax) {
            return uint256(1e18);
        }

        IJoePair pair = IJoePair(joeFactory.getPair(tokenAddress, wavax));

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        address token0Address = pair.token0();

        if (token0Address == wavax) {
            return (reserve1.mul(uint256(1e18))) / reserve0; // 18
        } else {
            return (reserve0.mul(uint256(1e18))) / reserve1; // 18
        }
    }

    struct FarmPair {
        address lpAddress;
        address token0Address;
        address token1Address;
        string token0Symbol;
        string token1Symbol;
        address masterChefAddress;
        uint256 masterChefBalance;
        uint256 reserveUSD;
        uint256 totalSupply;
    }

    function getFarmPairs(address[] calldata pairAddresses, address chefAddress) public view returns (FarmPair[] memory) {
        FarmPair[] memory farmPairs = new FarmPair[](pairAddresses.length);

        for (uint256 i = 0; i < pairAddresses.length; i++) {
            // get LP Address and masterChefBalance of LP
            IJoePair lpToken = IJoePair(pairAddresses[i]);
            address lpAddress = address(lpToken);
            uint256 balance = lpToken.balanceOf(chefAddress);
            farmPairs[i].lpAddress = lpAddress;
            farmPairs[i].masterChefBalance = balance;
            farmPairs[i].masterChefAddress = chefAddress;

            // get pair information
            address token0Address = lpToken.token0();
            address token1Address = lpToken.token1();
            farmPairs[i].token0Address = token0Address;
            farmPairs[i].token1Address = token1Address;
            farmPairs[i].token0Symbol = IJoeERC20(token0Address).symbol();
            farmPairs[i].token1Symbol = IJoeERC20(token1Address).symbol();

            // calculate reserveUSD of pair
            (uint256 reserve0, uint256 reserve1, ) = lpToken.getReserves(); // reserve0, reserve1 are 18 decimals
            uint256 token0PriceInAvax = getPriceInAvax(token0Address); // 18
            uint256 token1PriceInAvax = getPriceInAvax(token1Address); // 18
            uint256 token0ReserveUSD = reserve0.mul(token0PriceInAvax).mul(getAvaxPrice()); // 18.mul(18).mul(18) = 54 decimals 
            uint256 token1ReserveUSD = reserve1.mul(token1PriceInAvax).mul(getAvaxPrice()); // 54
            farmPairs[i].reserveUSD = token0ReserveUSD.add(token1ReserveUSD) / uint256(1e36); //54 decimals after adding? 18 after division

            // calculate total supply
            farmPairs[i].totalSupply = lpToken.totalSupply();
        }

        return farmPairs;
    }

    // Don't think this is needed 
    struct LiquidityPositionData {
        IJoeERC20 lpToken;
        uint256 balance; 
    }

    // Get the liquidity positions and the balance held by a MasterChef contract
    function getLiquidityPositionsFromChefs(address chefAddress) public view returns (LiquidityPositionData[] memory) {
        IMasterChef chefObj = IMasterChef(chefAddress);
        uint256 length = chefObj.poolLength();
        LiquidityPositionData[] memory lps = new LiquidityPositionData[](length);

        for (uint256 pid = 0; pid < length; pid++) {
            IJoeERC20 lpToken = chefObj.poolInfo(pid).lpToken;
            uint256 balance = lpToken.balanceOf(chefAddress);
            lps[pid].lpToken = lpToken;
            lps[pid].balance = balance;
        }
       
        return lps;
    }
}
