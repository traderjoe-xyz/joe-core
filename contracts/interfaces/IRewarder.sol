// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
import "../libraries/SafeERC20.sol";

interface IRewarder {
    using SafeERC20 for IERC20;

    function onJoeReward(address user, uint256 newLpAmount) external;

    function pendingTokens(address user)
        external
        view
        returns (uint256 pending);

    function rewardToken() external view returns (IERC20);
}
