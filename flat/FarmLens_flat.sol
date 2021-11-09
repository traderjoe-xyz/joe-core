// SPDX-License-Identifier: MIXED

// File contracts/libraries/SafeMath.sol
// License-Identifier: MIT
pragma solidity 0.6.12;

// a library for performing overflow-safe math, updated with awesomeness from of DappHub (https://github.com/dapphub/ds-math)
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require((c = a + b) >= b, "SafeMath: Add Overflow");
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require((c = a - b) <= a, "SafeMath: Underflow");
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b == 0 || (c = a * b) / b == a, "SafeMath: Mul Overflow");
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b > 0, "SafeMath: Div by Zero");
        c = a / b;
    }

    function to128(uint256 a) internal pure returns (uint128 c) {
        require(a <= uint128(-1), "SafeMath: uint128 Overflow");
        c = uint128(a);
    }
}

library SafeMath128 {
    function add(uint128 a, uint128 b) internal pure returns (uint128 c) {
        require((c = a + b) >= b, "SafeMath: Add Overflow");
    }

    function sub(uint128 a, uint128 b) internal pure returns (uint128 c) {
        require((c = a - b) <= a, "SafeMath: Underflow");
    }
}

// File contracts/interfaces/IERC20.sol
// License-Identifier: MIT
pragma solidity 0.6.12;

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // EIP 2612
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

// File contracts/libraries/SafeERC20.sol
// License-Identifier: MIT
pragma solidity 0.6.12;

library SafeERC20 {
    function safeSymbol(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(0x95d89b41));
        return success && data.length > 0 ? abi.decode(data, (string)) : "???";
    }

    function safeName(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(0x06fdde03));
        return success && data.length > 0 ? abi.decode(data, (string)) : "???";
    }

    function safeDecimals(IERC20 token) public view returns (uint8) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(0x313ce567));
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: Transfer failed");
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(0x23b872dd, from, address(this), amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: TransferFrom failed");
    }
}

// File contracts/traderjoe/interfaces/IJoeERC20.sol
// License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

interface IJoeERC20 {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

// File contracts/traderjoe/interfaces/IJoePair.sol
// License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

interface IJoePair {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

// File contracts/traderjoe/interfaces/IJoeFactory.sol
// License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

interface IJoeFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function migrator() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;

    function setMigrator(address) external;
}

// File contracts/boringcrypto/BoringOwnable.sol
// License-Identifier: MIT
pragma solidity 0.6.12;

// Audit on 5-Jan-2021 by Keno and BoringCrypto
// Source: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol + Claimable.sol
// Edited by BoringCrypto

contract BoringOwnableData {
    address public owner;
    address public pendingOwner;
}

contract BoringOwnable is BoringOwnableData {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice `owner` defaults to msg.sender on construction.
    constructor() public {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /// @notice Transfers ownership to `newOwner`. Either directly or claimable by the new pending owner.
    /// Can only be invoked by the current `owner`.
    /// @param newOwner Address of the new owner.
    /// @param direct True if `newOwner` should be set immediately. False if `newOwner` needs to use `claimOwnership`.
    /// @param renounce Allows the `newOwner` to be `address(0)` if `direct` and `renounce` is True. Has no effect otherwise.
    function transferOwnership(
        address newOwner,
        bool direct,
        bool renounce
    ) public onlyOwner {
        if (direct) {
            // Checks
            require(newOwner != address(0) || renounce, "Ownable: zero address");

            // Effects
            emit OwnershipTransferred(owner, newOwner);
            owner = newOwner;
            pendingOwner = address(0);
        } else {
            // Effects
            pendingOwner = newOwner;
        }
    }

    /// @notice Needs to be called by `pendingOwner` to claim ownership.
    function claimOwnership() public {
        address _pendingOwner = pendingOwner;

        // Checks
        require(msg.sender == _pendingOwner, "Ownable: caller != pending owner");

        // Effects
        emit OwnershipTransferred(owner, _pendingOwner);
        owner = _pendingOwner;
        pendingOwner = address(0);
    }

    /// @notice Only allows the `owner` to execute the function.
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }
}

// File contracts/traderjoe/FarmLens.sol
// License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;





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

    function getAvaxPrice() public view returns (uint256) {
        uint256 priceFromWavaxUsdt = _getAvaxPrice(IJoePair(address(0xeD8CBD9F0cE3C6986b22002F03c6475CEb7a6256))); // 18
        uint256 priceFromWavaxUsdc = _getAvaxPrice(IJoePair(address(0x87Dee1cC9FFd464B79e058ba20387c1984aed86a))); // 18
        uint256 priceFromWavaxDai = _getAvaxPrice(IJoePair(address(0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1))); // 18

        uint256 sumPrice = priceFromWavaxUsdt.add(priceFromWavaxUsdc).add(priceFromWavaxDai); // 18
        uint256 avaxPrice = sumPrice / 3; // 18
        return avaxPrice; // 18
    }

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

    function getPriceInUSD(address tokenAddress) public view returns (uint256) {
        return (getAvaxPrice().mul(getPriceInAvax(tokenAddress))) / 1e18; // 18
    }

    // Need to be aware of decimals here, not always 18, it depends on the token
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

    function _tokenDecimalsMultiplier(address tokenAddress) private pure returns (uint256) {
        uint256 decimalsNeeded = 18 - IJoeERC20(tokenAddress).decimals();
        return 1 * (10**decimalsNeeded);
    }

    function getReserveUSD(IJoePair pair) public view returns (uint256) {
        address token0Address = pair.token0();
        address token1Address = pair.token1();

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves(); 
        
        reserve0 = reserve0.mul(_tokenDecimalsMultiplier(token0Address)); // 18
        reserve1 = reserve1.mul(_tokenDecimalsMultiplier(token1Address)); // 18

        uint256 token0PriceInAvax = getPriceInAvax(token0Address); // 18
        uint256 token1PriceInAvax = getPriceInAvax(token1Address); // 18
        uint256 reserve0Avax = reserve0.mul(token0PriceInAvax); // 36; 
        uint256 reserve1Avax = reserve1.mul(token1PriceInAvax); // 36;
        uint256 reserveAVAX = (reserve0Avax.add(reserve1Avax)) / 1e18; // 18  
        uint256 reserveUSD = (reserveAVAX.mul(getAvaxPrice())) / 1e18; // 18 

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
        uint256 farmCount;
        uint256 farmPairIndex = 0;
        // get count of farm pairs that this masterChef owns, needed due to solidity lacking dynamic memory array support
         for (uint256 i = 0; i < pairAddresses.length; i++) {
            IJoePair lpToken = IJoePair(pairAddresses[i]);
            uint256 balance = lpToken.balanceOf(chefAddress);
            if (balance > 0) {
                farmCount++;
            }
        }

        FarmPair[] memory farmPairs = new FarmPair[](farmCount);

        for (uint256 i = 0; i < pairAddresses.length; i++) {
            IJoePair lpToken = IJoePair(pairAddresses[i]);

            // filtering out farms that chef has no balance in
            uint256 balance = lpToken.balanceOf(chefAddress);
            if (balance == 0) { continue; } 

            // get pair information
            address lpAddress = address(lpToken);
            address token0Address = lpToken.token0();
            address token1Address = lpToken.token1();
            farmPairs[farmPairIndex].lpAddress = lpAddress;
            farmPairs[farmPairIndex].token0Address = token0Address;
            farmPairs[farmPairIndex].token1Address = token1Address;
            farmPairs[farmPairIndex].token0Symbol = IJoeERC20(token0Address).symbol();
            farmPairs[farmPairIndex].token1Symbol = IJoeERC20(token1Address).symbol();

            // calculate reserveUSD of lp
            farmPairs[farmPairIndex].reserveUSD = getReserveUSD(lpToken); // 18

            // calculate total supply of lp
            farmPairs[farmPairIndex].totalSupply = lpToken.totalSupply().mul(_tokenDecimalsMultiplier(lpAddress));

            // get masterChef data
            farmPairs[farmPairIndex].chefBalance = balance.mul(_tokenDecimalsMultiplier(lpAddress));
            farmPairs[farmPairIndex].chefAddress = chefAddress;
            farmPairs[farmPairIndex].chefTotalAlloc = IMasterChef(chefAddress).totalAllocPoint();
            farmPairs[farmPairIndex].chefJoePerSec = IMasterChef(chefAddress).joePerSec();
            farmPairIndex++;
        }

        return farmPairs;
    }

    struct AllFarmData {
        uint256 avaxPriceUSD;
        uint256 joePriceUSD;
        uint256 totalAllocChefV2;
        uint256 totalAllocChefV3;
        uint256 joePerSecChefV2;
        uint256 joePerSecChefV3;
        FarmPair[] farmPairsV2;
        FarmPair[] farmPairsV3;
    }

    function getAllFarmData(address[] calldata pairAddresses) public view returns (AllFarmData memory) {
        AllFarmData memory allFarmData;

        allFarmData.avaxPriceUSD = getAvaxPrice();
        allFarmData.joePriceUSD = getPriceInUSD(joe);

        allFarmData.totalAllocChefV2 = IMasterChef(chefv2).totalAllocPoint();
        allFarmData.joePerSecChefV2 = IMasterChef(chefv2).joePerSec();

        allFarmData.totalAllocChefV3 = IMasterChef(chefv3).totalAllocPoint();
        allFarmData.joePerSecChefV3 = IMasterChef(chefv3).joePerSec();

        allFarmData.farmPairsV2 = getFarmPairs(pairAddresses, address(chefv2));
        allFarmData.farmPairsV3 = getFarmPairs(pairAddresses, address(chefv3));

        return allFarmData;
    }
}