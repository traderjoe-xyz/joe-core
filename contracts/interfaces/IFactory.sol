// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IFactory {
    function allPairsLength() external view returns (uint256);

    function allPairs(uint256 i) external view returns (address);

    function getPair(address token0, address token1) external view returns (address);

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);
}
