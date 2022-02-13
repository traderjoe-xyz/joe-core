// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "../libraries/BoringJoeERC20.sol";

interface IMasterChefJoe {
    using BoringJoeERC20 for IERC20;
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. JOE to distribute per block.
        uint256 lastRewardTimestamp; // Last block number that JOE distribution occurs.
        uint256 accJoePerShare; // Accumulated JOE per share, times 1e12. See below.
    }

    function userInfo(uint256 _pid, address _user) external view returns (IMasterChefJoe.UserInfo memory);

    function poolInfo(uint256 pid) external view returns (IMasterChefJoe.PoolInfo memory);

    function totalAllocPoint() external view returns (uint256);

    function joePerSec() external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function devPercent() external view returns (uint256);

    function treasuryPercent() external view returns (uint256);

    function investorPercent() external view returns (uint256);
}
