// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../boringcrypto/BoringOwnable.sol";
import "../libraries/SafeERC20.sol";

interface IBarV2 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function entryFee() external view returns (uint256);
}

/**
 * This is a sample contract to be used in the JoeBarV2 to reward moJoe holder with JOE.
 *
 * It assumes no minting rights, so requires a set amount of YOUR_TOKEN to be transferred to this contract prior.
 * E.g. say you've allocated 100,000 XYZ to the JOE-XYZ farm over 30 days. Then you would need to transfer
 * 100,000 XYZ and set the block reward accordingly so it's fully distributed after 30 days.
 *
 */
contract BarRewarderPerSec is BoringOwnable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable joe;
    IBarV2 public bar;
    uint256 public apr;

    uint256 private secondsPerYear = 365 days;

    uint256 public lastRewardTimestamp;
    uint256 public tokenPerSec;

    uint256 public unpaidRewards;

    event ClaimReward(uint256 amount);
    event UpdateApr(uint256 oldRate, uint256 newRate);

    bool private initialized;

    modifier onlyBar() {
        require(msg.sender == address(bar), "onlyBar: only JoeBar can call this function");
        _;
    }

    constructor(IERC20 _joe, uint256 _apr) public {
        require(Address.isContract(address(_joe)), "constructor: reward token must be a valid contract");

        joe = _joe;
        setApr(_apr);
        lastRewardTimestamp = block.timestamp;
        tokenPerSec = 0;
    }

    function initialize() public {
        require(!initialized, "BarRewarderV2: Already initialized");

        lastRewardTimestamp = block.timestamp;
        bar = IBarV2(msg.sender);
        initialized = true;
    }

    /// @notice Update reward variables.
    function update() public {
        if (block.timestamp > lastRewardTimestamp) {
            uint256 barSupply = bar.totalSupply();
            if (barSupply > 0) {
                uint256 timeElapsed = block.timestamp.sub(lastRewardTimestamp);
                tokenPerSec = barSupply.mul(apr).div(10000).div(secondsPerYear);
                unpaidRewards = unpaidRewards.add(timeElapsed.mul(tokenPerSec));
            }

            lastRewardTimestamp = block.timestamp;
        }
    }

    /// @notice Sets the APR.
    /// @param _apr The new APR
    function setApr(uint256 _apr) public onlyOwner {
        require(_apr <= 10000, "BarRewarderPerSec: Apr can't be greater than 100%");
        uint256 oldApr = apr;
        apr = _apr; // in basis points aka parts per 10,000 so 5000 is 50%, apr of 50%.
        //        apr = _apr.mul(10_000).div(10_000 - IBarV2.entryFee()); // if added then when bar updates its fees
        //                                                          this needs to be called to update the actual JOE apr

        emit UpdateApr(oldApr, _apr);
    }

    /// @notice Function called by JoeBar whenever staker enters or leaves moJOE.
    function claimReward() external onlyBar nonReentrant {
        update();
        uint256 pending = unpaidRewards;

        if (bar.totalSupply() > 0) {
            uint256 balance = joe.balanceOf(address(this));
            if (pending > balance) {
                joe.safeTransfer(address(bar), balance);
                unpaidRewards = pending - balance;
            } else {
                joe.safeTransfer(address(bar), pending);
                unpaidRewards = 0;
            }
        }

        emit ClaimReward(pending - unpaidRewards);
    }

    /// @notice In case rewarder is stopped before emissions finished, this function allows
    /// withdrawal of remaining tokens.
    function emergencyWithdraw() public onlyOwner {
        joe.safeTransfer(address(msg.sender), joe.balanceOf(address(this)));
    }

    /// @notice View function to see balance of reward token.
    function balance() external view returns (uint256) {
        return joe.balanceOf(address(this));
    }
}
