// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

interface IWAVAX {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}
