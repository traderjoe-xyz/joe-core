// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IBarRewarder {
    function claimReward() external;
}

// JoeBar is the coolest bar in town. You come in with some Joe, and leave with more! The longer you stay, the more Joe you get.
//
// This contract handles swapping to and from moJoe, JoeSwap's staking token.
contract JoeBarV2 is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    IERC20Upgradeable public joe;
    IBarRewarder public rewarder;
    uint256 public entryFee;

    event SetEntryFee(uint256 _entryFee);
    event SetRewarder(address _rewarder);

    // Define the Joe token contract
    function initialize(IERC20Upgradeable _joe, uint256 _entryFee) public initializer {
        __ERC20_init("JoeBarV2", "moJOE");
        __Ownable_init();

        joe = _joe;
        setEntryFee(_entryFee);
    }

    // Enter the bar. Pay some JOEs. Earn some shares.
    // Locks Joe and mints moJoe
    function enter(uint256 _amount) external {
        // Gets the rewards
        rewarder.claimReward();

        uint256 fee = _amount.mul(entryFee).div(10000);
        uint256 amount = _amount.sub(fee);

        // Gets the amount of Joe locked in the contract
        uint256 totalJoe = joe.balanceOf(address(this));
        // Gets the amount of moJoe in existence
        uint256 totalShares = totalSupply();
        // If no moJoe exists, mint it 1:1 to the amount (minus the fees) put in
        if (totalShares == 0 || totalJoe == 0) {
            require(_amount >= 1e18, "JoeBarV2: You need to enter with at least 1 $JOE.");
            _mint(msg.sender, amount);
        }
        // Calculate and mint the amount of moJoe the Joe is worth. The ratio will change overtime, as moJoe is
        // burned/minted and Joe deposited + gained from fees / withdrawn.
        else {
            uint256 what = amount.mul(totalShares).div(totalJoe);
            _mint(msg.sender, what);
        }
        // Lock the Joe in the contract
        joe.transferFrom(msg.sender, address(this), amount);
        joe.transferFrom(msg.sender, address(rewarder), fee);
    }

    // Leave the bar. Claim back your JOEs.
    // Unlocks the staked + gained Joe and burns moJoe
    function leave(uint256 _share) external {
        // Gets the rewards
        rewarder.claimReward();

        // Gets the amount of moJoe in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of Joe the moJoe is worth
        uint256 what = _share.mul(joe.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        joe.transfer(msg.sender, what);
    }

    // Set the entryFee for moJoe.
    function setEntryFee(uint256 _entryFee) public onlyOwner {
        require(_entryFee <= 5000, "JoeBarV2: entryFee too high");
        entryFee = _entryFee;

        emit SetEntryFee(_entryFee);
    }

    function setRewarder(IBarRewarder _rewarder) external onlyOwner {
        rewarder = _rewarder;

        emit SetRewarder(address(_rewarder));
    }
}
