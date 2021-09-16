// SPDX-License-Identifier: MIT

/**
 *Submitted for verification at Etherscan.io on 2020-10-09
 */

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IFactory.sol";

interface IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function owner() external view returns (address);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
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
        // Use max uint256 to signal failure to retrieve nonce (probably not supported)
        return success && data.length == 32 ? abi.decode(data, (uint256)) : uint256(-1);
    }
}

interface IMasterChef {
    function BONUS_MULTIPLIER() external view returns (uint256);

    function devaddr() external view returns (address);

    function owner() external view returns (address);

    function startTimestamp() external view returns (uint256);

    function joe() external view returns (address);

    function joePerSec() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function poolLength() external view returns (uint256);

    function poolInfo(uint256 nr)
        external
        view
        returns (
            address,
            uint256,
            uint256,
            uint256
        );

    function userInfo(uint256 nr, address who) external view returns (uint256, uint256);

    function pendingTokens(uint256 pid, address who)
        external
        view
        returns (
            uint256,
            address,
            string memory,
            uint256
        );
}

interface IPair is IERC20 {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112,
            uint112,
            uint32
        );
}

contract BoringCryptoDashboardV2 {
    using SafeMath for uint256;

    struct PairFull {
        address token;
        address token0;
        address token1;
        uint256 reserve0;
        uint256 reserve1;
        uint256 totalSupply;
        uint256 balance;
    }

    function getPairsFull(address who, address[] calldata addresses) public view returns (PairFull[] memory) {
        PairFull[] memory pairs = new PairFull[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            address token = addresses[i];
            pairs[i].token = token;
            pairs[i].token0 = IPair(token).token0();
            pairs[i].token1 = IPair(token).token1();
            (uint256 reserve0, uint256 reserve1, ) = IPair(token).getReserves();
            pairs[i].reserve0 = reserve0;
            pairs[i].reserve1 = reserve1;
            pairs[i].balance = IERC20(token).balanceOf(who);
            pairs[i].totalSupply = IERC20(token).totalSupply();
        }
        return pairs;
    }

    struct PoolsInfo {
        uint256 totalAllocPoint;
        uint256 poolLength;
    }

    struct PoolInfo {
        uint256 pid;
        IPair lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. SUSHIs to distribute per block.
        address token0;
        address token1;
    }

    IMasterChef chef;
    IFactory pangolinFactory;
    IFactory joeFactory;
    address wavax;

    constructor(
        address _chef,
        address _pangolinFactory,
        address _joeFactory,
        address _wavax
    ) public {
        chef = IMasterChef(_chef);
        pangolinFactory = IFactory(_pangolinFactory);
        joeFactory = IFactory(_joeFactory);
        wavax = _wavax;
    }

    function getPools(uint256[] calldata pids) public view returns (PoolsInfo memory, PoolInfo[] memory) {
        PoolsInfo memory info;
        info.totalAllocPoint = chef.totalAllocPoint();
        uint256 poolLength = chef.poolLength();
        info.poolLength = poolLength;

        PoolInfo[] memory pools = new PoolInfo[](pids.length);

        for (uint256 i = 0; i < pids.length; i++) {
            pools[i].pid = pids[i];
            (address lpToken, uint256 allocPoint, , ) = chef.poolInfo(pids[i]);
            IPair pair = IPair(lpToken);
            pools[i].lpToken = pair;
            pools[i].allocPoint = allocPoint;

            pools[i].token0 = pair.token0();
            pools[i].token1 = pair.token1();
        }
        return (info, pools);
    }

    function findPools(address who, uint256[] calldata pids) public view returns (PoolInfo[] memory) {
        uint256 count;

        for (uint256 i = 0; i < pids.length; i++) {
            (uint256 balance, ) = chef.userInfo(pids[i], who);
            if (balance > 0) {
                count++;
            }
        }

        PoolInfo[] memory pools = new PoolInfo[](count);

        count = 0;
        for (uint256 i = 0; i < pids.length; i++) {
            (uint256 balance, ) = chef.userInfo(pids[i], who);
            if (balance > 0) {
                pools[count].pid = pids[i];
                (address lpToken, uint256 allocPoint, , ) = chef.poolInfo(pids[i]);
                IPair pair = IPair(lpToken);
                pools[count].lpToken = pair;
                pools[count].allocPoint = allocPoint;

                pools[count].token0 = pair.token0();
                pools[count].token1 = pair.token1();
                count++;
            }
        }

        return pools;
    }

    function getAVAXRate(address token) public view returns (uint256) {
        uint256 avax_rate = 1e18;
        if (token != wavax) {
            IPair pairPangolin;
            IPair pairJoe;
            pairPangolin = IPair(IFactory(pangolinFactory).getPair(token, wavax));
            pairJoe = IPair(IFactory(joeFactory).getPair(token, wavax));
            if (address(pairPangolin) == address(0) && address(pairJoe) == address(0)) {
                return 0;
            }

            uint112 reserve0Pangolin;
            uint112 reserve1Pangolin;
            uint112 reserve0Joe;
            uint112 reserve1Joe;

            if (address(pairPangolin) != address(0)) {
                (reserve0Pangolin, reserve1Pangolin, ) = pairPangolin.getReserves();
            }
            if (address(pairJoe) != address(0)) {
                (reserve0Joe, reserve1Joe, ) = pairJoe.getReserves();
            }

            if (address(pairJoe) == address(0) || reserve0Pangolin > reserve0Joe || reserve1Pangolin > reserve1Joe) {
                if (pairPangolin.token0() == wavax) {
                    avax_rate = uint256(reserve1Pangolin).mul(1e18).div(reserve0Pangolin);
                } else {
                    avax_rate = uint256(reserve0Pangolin).mul(1e18).div(reserve1Pangolin);
                }
            } else {
                if (pairJoe.token0() == wavax) {
                    avax_rate = uint256(reserve1Joe).mul(1e18).div(reserve0Joe);
                } else {
                    avax_rate = uint256(reserve0Joe).mul(1e18).div(reserve1Joe);
                }
            }
        }
        return avax_rate;
    }

    struct UserPoolInfo {
        uint256 pid;
        uint256 balance; // Balance of pool tokens
        uint256 totalSupply; // Token staked lp tokens
        uint256 lpBalance; // Balance of lp tokens not staked
        uint256 lpTotalSupply; // TotalSupply of lp tokens
        uint256 lpAllowance; // LP tokens approved for masterchef
        uint256 reserve0;
        uint256 reserve1;
        uint256 token0rate;
        uint256 token1rate;
        uint256 rewardDebt;
        uint256 pending; // Pending JOE
    }

    function pollPools(address who, uint256[] calldata pids) public view returns (UserPoolInfo[] memory) {
        UserPoolInfo[] memory pools = new UserPoolInfo[](pids.length);

        for (uint256 i = 0; i < pids.length; i++) {
            (uint256 amount, ) = chef.userInfo(pids[i], who);
            pools[i].balance = amount;
            (uint256 pendingJoe, , , ) = chef.pendingTokens(pids[i], who);
            pools[i].pending = pendingJoe;

            (address lpToken, , , ) = chef.poolInfo(pids[i]);
            pools[i].pid = pids[i];
            IPair pair = IPair(lpToken);
            pools[i].totalSupply = pair.balanceOf(address(chef));
            pools[i].lpAllowance = pair.allowance(who, address(chef));
            pools[i].lpBalance = pair.balanceOf(who);
            pools[i].lpTotalSupply = pair.totalSupply();
            pools[i].token0rate = getAVAXRate(pair.token0());
            pools[i].token1rate = getAVAXRate(pair.token1());

            (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
            pools[i].reserve0 = reserve0;
            pools[i].reserve1 = reserve1;
        }
        return pools;
    }
}
