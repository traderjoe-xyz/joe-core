// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// JoeBar is the coolest bar in town. You come in with some Joe, and leave with more! The longer you stay, the more Joe you get.
//
// This contract handles swapping to and from xJoe, JoeSwap's staking token.
contract JoeBar is ERC20("JoeBar", "xJOE") {
    using SafeMath for uint256;
    IERC20 public joe;

    // Define the Joe token contract
    constructor(IERC20 _joe) public {
        joe = _joe;
    }

    // Enter the bar. Pay some JOEs. Earn some shares.
    // Locks Joe and mints xJoe
    function enter(uint256 _amount) public {
        // Gets the amount of Joe locked in the contract
        uint256 totalJoe = joe.balanceOf(address(this));
        // Gets the amount of xJoe in existence
        uint256 totalShares = totalSupply();
        // If no xJoe exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalJoe == 0) {
            _mint(msg.sender, _amount);
        }
        // Calculate and mint the amount of xJoe the Joe is worth. The ratio will change overtime, as xJoe is burned/minted and Joe deposited + gained from fees / withdrawn.
        else {
            uint256 what = _amount.mul(totalShares).div(totalJoe);
            _mint(msg.sender, what);
        }
        // Lock the Joe in the contract
        joe.transferFrom(msg.sender, address(this), _amount);
    }

    // Leave the bar. Claim back your JOEs.
    // Unlocks the staked + gained Joe and burns xJoe
    function leave(uint256 _share) public {
        // Gets the amount of xJoe in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of Joe the xJoe is worth
        uint256 what = _share.mul(joe.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        joe.transfer(msg.sender, what);
    }
}
