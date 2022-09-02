// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../StableJoeStaking.sol";

contract StableJoeVaultMock {
    IERC20 public immutable joe;
    StableJoeStaking public immutable sJoe;

    constructor(IERC20 _joe, StableJoeStaking _sJoe) public {
        joe = _joe;
        sJoe = _sJoe;
    }

    function deposit(uint256 _amount) external {
        joe.transferFrom(msg.sender, address(this), _amount);
        joe.approve(address(sJoe), _amount);
        sJoe.deposit(_amount);
    }
}
