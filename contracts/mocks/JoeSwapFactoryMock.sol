// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../traderjoe/JoeFactory.sol";

contract JoeSwapFactoryMock is JoeFactory {
    constructor(address _feeToSetter) public JoeFactory(_feeToSetter) {}
}
