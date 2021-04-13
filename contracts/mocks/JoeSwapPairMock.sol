// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../traderjoe/JoePair.sol";

contract JoeSwapPairMock is JoePair {
    constructor() public JoePair() {}
}
