// SPDX-License-Identifier: MIT

/// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IBarRewarder {
    function initialize(address _bar) external;
    function claimReward() external;
}

/**
 * @title Joe Bar V2
 * @author traderjoexyz
 * @notice JoeBar is the coolest bar in town. You come in with some JOE, and leave with more!
 * The longer you stay, the more JOE you get. This contract handles swapping to and from moJOE,
 * One of TraderJoe's staking token.
 * @dev All public/external functions are tested in `./test/JoeBarV2.test.ts`.
 */
contract JoeBarV2 is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    /// @notice JOE Token address
    IERC20Upgradeable public joe;

    /*
     * @notice Rewarder address
     * @dev Needs to be set up after deploying barV2
     */
    IBarRewarder public rewarder;

    /// @notice entry fee, in basis points aka parts per 10,000 so 5000 is 50%, entry fee of 50%.
    uint256 public entryFee;

    /// @notice Emitted when owner set the entry fee.
    event SetEntryFee(uint256 _entryFee);

    /// @notice Emitted when owner set the rewarder.
    event SetRewarder(address _rewarder);

    /// @notice Defines the moJOE token contract
    function initialize(address _joe, address _rewarder, uint256 _entryFee) public initializer {
        __ERC20_init("JoeBarV2", "moJOE");
        __Ownable_init();

        joe = IERC20Upgradeable(_joe);
        setEntryFee(_entryFee);

        (bool success, ) = _rewarder.call.value(0)(abi.encodeWithSignature("initialize()", 0));
        require(success, "JoeBarV2: Failed to initialize rewarder");
        setRewarder(IBarRewarder(_rewarder));
    }

    /**
     * @notice Enter the bar. Pay some JOEs. Earn some shares. Locks Joe and mints moJoe.
     * @param _amount The amount of JOE to send to bar
     */
    function enter(uint256 _amount) external {
        /// Claims the rewards
        rewarder.claimReward();

        uint256 fee = _amount.mul(entryFee).div(10_000);
        uint256 amountSubFee = _amount.sub(fee);

        /// Gets the amount of JOE locked in the contract
        uint256 totalJoe = joe.balanceOf(address(this));
        /// Gets the amount of moJOE in existence
        uint256 totalShares = totalSupply();
        /// If no moJoe exists, mint it 1:1 to the amount (minus the fees) put in
        if (totalShares == 0 || totalJoe == 0) {
            require(_amount >= 1e18, "JoeBarV2: You need to enter with at least 1 $JOE.");
            _mint(msg.sender, amountSubFee);
        }
        /// Calculate and mint the amount of moJOE the JOE is worth. The ratio will change overtime, as moJOE is
        /// burned/minted and JOE deposited + gained from fees / withdrawn.
        else {
            uint256 what = amountSubFee.mul(totalShares).div(totalJoe);
            _mint(msg.sender, what);
        }
        /// Locks JOE in the contract
        joe.transferFrom(msg.sender, address(this), amountSubFee);
        /// Sends the fee to the rewarder
        joe.transferFrom(msg.sender, address(rewarder), fee);
    }

    /**
     * @notice Leave the bar. Claim back your JOEs. Unlocks the staked + gained JOE and burns moJOE.
     * @param _share The amount of moJOE to convert to JOE.
     */
    function leave(uint256 _share) external {
        /// Claims the rewards
        rewarder.claimReward();

        /// Gets the amount of moJOE in existence
        uint256 totalShares = totalSupply();
        /// Calculates the amount of JOE the moJOE is worth
        uint256 what = _share.mul(joe.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        joe.transfer(msg.sender, what);
    }

    /**
     * @notice Set the entryFee for moJOE. Can't be higher than 5_000 (50%).
     * @param _entryFee The new entry fee.
     */
    function setEntryFee(uint256 _entryFee) public onlyOwner {
        require(_entryFee <= 5_000, "JoeBarV2: entryFee too high");
        entryFee = _entryFee;

        emit SetEntryFee(_entryFee);
    }

    /**
     * @notice Set the rewarder for moJOE.
     * @dev Needs to be set up after deploying.
     * @param _rewarder The new rewarder.
     */
    function setRewarder(IBarRewarder _rewarder) public onlyOwner {
        rewarder = _rewarder;

        emit SetRewarder(address(_rewarder));
    }
}
