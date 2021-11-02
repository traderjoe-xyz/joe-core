SPDX-License-Identifier: MIT

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// Version 22-Mar-2021

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function owner() external view returns (address);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IPair is IERC20 {
    function token0() external view returns (IERC20);

    function token1() external view returns (IERC20);

    function getReserves()
        external
        view
        returns (
            uint112,
            uint112,
            uint32
        );
}

interface IFactory {
    function allPairsLength() external view returns (uint256);

    function allPairs(uint256 i) external view returns (IPair);

    function getPair(IERC20 token0, IERC20 token1) external view returns (IPair);

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);
}

library BoringMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require((c = a + b) >= b, "BoringMath: Add Overflow");
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require((c = a - b) <= a, "BoringMath: Underflow");
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b == 0 || (c = a * b) / b == a, "BoringMath: Mul Overflow");
    }
}

contract Ownable {
    address public immutable owner;

    constructor() internal {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }
}

library BoringERC20 {
    function returnDataToString(bytes memory data) internal pure returns (string memory) {
        if (data.length >= 64) {
            return abi.decode(data, (string));
        } else if (data.length == 32) {
            uint8 i = 0;
            while (i < 32 && data[i] != 0) {
                i++;
            }
            bytes memory bytesArray = new bytes(i);
            for (i = 0; i < 32 && data[i] != 0; i++) {
                bytesArray[i] = data[i];
            }
            return string(bytesArray);
        } else {
            return "???";
        }
    }

    function symbol(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(0x95d89b41));
        return success ? returnDataToString(data) : "???";
    }

    function name(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(0x06fdde03));
        return success ? returnDataToString(data) : "???";
    }

    function decimals(IERC20 token) internal view returns (uint8) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(0x313ce567));
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }

    function DOMAIN_SEPARATOR(IERC20 token) internal view returns (bytes32) {
        (bool success, bytes memory data) = address(token).staticcall{gas: 10000}(abi.encodeWithSelector(0x3644e515));
        return success && data.length == 32 ? abi.decode(data, (bytes32)) : bytes32(0);
    }

    function nonces(IERC20 token, address owner) internal view returns (uint256) {
        (bool success, bytes memory data) = address(token).staticcall{gas: 5000}(
            abi.encodeWithSelector(0x7ecebe00, owner)
        );
        return success && data.length == 32 ? abi.decode(data, (uint256)) : uint256(-1); // Use max uint256 to signal failure to retrieve nonce (probably not supported)
    }
}

library BoringPair {
    function factory(IPair pair) internal view returns (IFactory) {
        (bool success, bytes memory data) = address(pair).staticcall(abi.encodeWithSelector(0xc45a0155));
        return success && data.length == 32 ? abi.decode(data, (IFactory)) : IFactory(0);
    }
}

contract JoeUseFarms is Ownable {
    using BoringMath for uint256;
    using BoringERC20 for IERC20;
    using BoringERC20 for IPair;
    using BoringPair for IPair;

    IERC20 public joe; // IJoeToken(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2);
    IERC20 public WAVAX; // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IERC20 public USDT; // 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    IERC20 public USDC; // 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
    IERC20 public DAI; // 0x6b175474e89094c44da98b954eedeac495271d0f
    IFactory public joeFactory; // IFactory(0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);
    IFactory public pangolinFactory; // IFactory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    constructor(
        IERC20 joe_,
        IERC20 WAVAX_,
        IERC20 USDT_,
        IERC20 USDC_,
        IERC20 DAI_,
        IFactory joeFactory_,
        IFactory pangolinFactory_
    ) public {
        joe = joe_;
        WAVAX = WAVAX;
        USDT = USDT;
        USDC = USDC;
        DAI = DAI;
        joeFactory = joeFactory_;
        pangolinFactory = pangolinFactory_;
    }

    function setContracts(
        IERC20 joe_,
        IERC20 WAVAX_,
        IERC20 USDT_,
        IERC20 USDC_,
        IERC20 DAI_,
        IFactory joeFactory_,
        IFactory pangolinFactory_
    ) public onlyOwner {
        joe = joe_;
        WAVAX = WAVAX_;
        USDT = USDT_;
        USDC = USDC_;
        DAI = DAI_;
        joeFactory = joeFactory_;
        pangolinFactory = pangolinFactory_;
    }

    function getAvaxPrice() public view returns (uint256) {
        address[3] memory WAVAX_STABLE_PAIRS = [
            address(0xeD8CBD9F0cE3C6986b22002F03c6475CEb7a6256), 
            address(0x87Dee1cC9FFd464B79e058ba20387c1984aed86a), 
            address(0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1)];
        uint256 total_weight = 0;
        uint256 sum_price = 0;

        for (uint256 i = 0; i < WAVAX_STABLE_PAIRS.length; ++i) {
            address pair_address = WAVAX_STABLE_PAIRS[i];
            IPair pair = IPair(pair_address);
            uint256 price = _getAvaxPrice(pair);
            uint256 weight = _getAvaxReserve(pair);

            total_weight = total_weight.add(weight);
            sum_price = sum_price.add(price.mul(weight));
        }

        // div by 0
        uint256 avax_price = total_weight == 0 ? 0 : sum_price / total_weight;
        return avax_price;
    }

    function _getAvaxPrice(IPair pair) public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        if (pair.token0() == WAVAX) {
            return (uint256(reserve1) * 1e18) / reserve0;
        } else {
            return (uint256(reserve0) * 1e18) / reserve1;
        }
    }

    function _getAvaxReserve(IPair pair) public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 reserve = pair.token0() == IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7) ? reserve0 : reserve1;
        return reserve;
    
    }

    function _getUSDPrice(IPair pair) public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        if (pair.token0() == USDT || pair.token0() == USDC || pair.token0() == DAI) {
            return (uint256(reserve1) * 1e18) / reserve0;
        } else {
            return (uint256(reserve0) * 1e18) / reserve1;
        }
    }

    function getAVAXRate(IERC20 token) public view returns (uint256) {
        if (token == WAVAX) {
            return 1e18;
        }
        IPair pairPangolin;
        IPair pairJoe;
        if (pangolinFactory != IFactory(0)) {
            pairPangolin = IPair(pangolinFactory.getPair(token, WAVAX));
        }
        if (joeFactory != IFactory(0)) {
            pairJoe = IPair(joeFactory.getPair(token, WAVAX));
        }
        if (address(pairPangolin) == address(0) && address(pairJoe) == address(0)) {
            return 0;
        }

        uint112 reserve0;
        uint112 reserve1;
        IERC20 token0;
        if (address(pairPangolin) != address(0)) {
            (uint112 reserve0Pangolin, uint112 reserve1Pangolin, ) = pairPangolin.getReserves();
            reserve0 += reserve0Pangolin;
            reserve1 += reserve1Pangolin;
            token0 = pairPangolin.token0();
        }

        if (address(pairJoe) != address(0)) {
            (uint112 reserve0Joe, uint112 reserve1Joe, ) = pairJoe.getReserves();
            reserve0 += reserve0Joe;
            reserve1 += reserve1Joe;
            if (token0 == IERC20(0)) {
                token0 = pairJoe.token0();
            }
        }

        if (token0 == WAVAX) {
            return (uint256(reserve1) * 1e18) / reserve0;
        } else {
            return (uint256(reserve0) * 1e18) / reserve1;
        }
    }

    struct UseFarmPair {
        IPair token;
        IERC20 token0;
        IERC20 token1;
        uint256 reserveUSD;
        uint256 totalSupply;
    }

    function getUseFarmPairs(IPair[] calldata addresses) public view returns (UseFarmPair[] memory) {
        UseFarmPair[] memory pairs = new UseFarmPair[](addresses.length);

        for (uint256 i = 0; i < addresses.length; i++) {
            IPair token = addresses[i];
            pairs[i].token = token;
            pairs[i].token0 = token.token0();
            pairs[i].token1 = token.token1();
            (uint256 reserve0, uint256 reserve1, ) = token.getReserves();
            uint256 token0AvaxRate = getAVAXRate(pairs[i].token0);
            uint256 token1AvaxRate = getAVAXRate(pairs[i].token1);
            uint256 token0ReserveUSD = reserve0 * token0AvaxRate * getAvaxPrice();
            uint256 token1ReserveUSD = reserve1 * token1AvaxRate * getAvaxPrice();
            pairs[i].reserveUSD = token0ReserveUSD + token1ReserveUSD;
            pairs[i].totalSupply = token.totalSupply();
        }
        return pairs;
    }
    struct LiquidityPositionData {
        IPair token;
        uint256 balance; 
    }

    function getLiquidityPositionData(address who) public view returns (LiquidityPositionData[] memory) {
        IPair token = who
    }
}
