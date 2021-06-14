// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IStrategy {
    function skim(uint256 amount) external;

    function harvest(uint256 balance, address sender)
        external
        returns (int256 amountAdded);

    function withdraw(uint256 amount) external returns (uint256 actualAmount);

    function exit(uint256 balance) external returns (int256 amountAdded);
}
