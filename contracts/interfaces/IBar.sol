// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IBar {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}
