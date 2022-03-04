// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./VeJoeToken.sol";

/// @title Vote Escrow Joe Staking
/// @author Trader Joe
/// @notice Stake JOE to earn veJOE, which you can use to earn higher farm yields and gain
/// voting power. Note that unstaking any amount of JOE will burn all of your existing veJOE.
contract VeJoeStaking is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Info for each user
    /// `balance`: Amount of JOE currently staked by user
    /// `rewardDebt`: The reward debt of the user
    /// `lastClaimTimestamp`: The timestamp of user's last claim or withdraw
    /// `speedUpEndTimestamp`: The timestamp when user stops receiving speed up benefits, or
    /// zero if user is not currently receiving speed up benefits
    struct UserInfo {
        uint256 balance;
        uint256 rewardDebt;
        uint256 lastClaimTimestamp;
        uint256 speedUpEndTimestamp;
        /**
         * @notice We do some fancy math here. Basically, any point in time, the amount of veJOE
         * entitled to a user but is pending to be distributed is:
         *
         *   pendingReward = pendingBaseReward + pendingSpeedUpReward
         *
         *   pendingBaseReward = (user.balance * accVeJoePerShare) - user.rewardDebt
         *
         *   if user.speedUpEndTimestamp != 0:
         *     speedUpCeilingTimestamp = min(block.timestamp, user.speedUpEndTimestamp)
         *     speedUpSecondsElapsed = speedUpCeilingTimestamp - user.lastClaimTimestamp
         *     pendingSpeedUpReward = speedUpSecondsElapsed * user.balance * speedUpVeJoePerSharePerSec
         *   else:
         *     pendingSpeedUpReward = 0
         */
    }

    IERC20Upgradeable public joe;
    VeJoeToken public veJoe;

    /// @notice The maximum limit of veJOE user can have as percentage points of staked JOE
    /// For example, if user has `n` JOE staked, they can own a maximum of `n * maxCapPct / 100` veJOE.
    uint256 public maxCapPct;

    /// @notice The upper limit of `maxCapPct`
    uint256 public upperLimitMaxCapPct;

    /// @notice The accrued veJoe per share, scaled to `ACC_VEJOE_PER_SHARE_PRECISION`
    uint256 public accVeJoePerShare;

    /// @notice Precision of `accVeJoePerShare`
    uint256 public ACC_VEJOE_PER_SHARE_PRECISION;

    /// @notice The last time that the reward variables were updated
    uint256 public lastRewardTimestamp;

    /// @notice veJOE per sec per JOE staked, scaled to `VEJOE_PER_SHARE_PER_SEC_PRECISION`
    uint256 public veJoePerSharePerSec;

    /// @notice Speed up veJOE per sec per JOE staked, scaled to `VEJOE_PER_SHARE_PER_SEC_PRECISION`
    uint256 public speedUpVeJoePerSharePerSec;

    /// @notice The upper limit of `veJoePerSharePerSec` and `speedUpVeJoePerSharePerSec`
    uint256 public upperLimitVeJoePerSharePerSec;

    /// @notice Precision of `veJoePerSharePerSec`
    uint256 public VEJOE_PER_SHARE_PER_SEC_PRECISION;

    /// @notice Percentage of user's current staked JOE user has to deposit in order to start
    /// receiving speed up benefits, in parts per 100.
    /// @dev Specifically, user has to deposit at least `speedUpThreshold/100 * userStakedJoe` JOE.
    /// The only exception is the user will also receive speed up benefits if they are depositing
    /// with zero balance
    uint256 public speedUpThreshold;

    /// @notice The length of time a user receives speed up benefits
    uint256 public speedUpDuration;

    mapping(address => UserInfo) public userInfos;

    event Claim(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event UpdateMaxCapPct(address indexed user, uint256 maxCapPct);
    event UpdateRewardVars(uint256 lastRewardTimestamp, uint256 accVeJoePerShare);
    event UpdateSpeedUpThreshold(address indexed user, uint256 speedUpThreshold);
    event UpdateVeJoePerSharePerSec(address indexed user, uint256 veJoePerSharePerSec);
    event Withdraw(address indexed user, uint256 amount);

    /// @notice Initialize with needed parameters
    /// @param _joe Address of the JOE token contract
    /// @param _veJoe Address of the veJOE token contract
    /// @param _veJoePerSharePerSec veJOE per sec per JOE staked, scaled to `VEJOE_PER_SHARE_PER_SEC_PRECISION`
    /// @param _speedUpVeJoePerSharePerSec Similar to `_veJoePerSharePerSec` but for speed up
    /// @param _speedUpThreshold Percentage of total staked JOE user has to deposit receive speed up
    /// @param _speedUpDuration Length of time a user receives speed up benefits
    /// @param _maxCapPct Maximum limit of veJOE user can have as percentage points of staked JOE
    function initialize(
        IERC20Upgradeable _joe,
        VeJoeToken _veJoe,
        uint256 _veJoePerSharePerSec,
        uint256 _speedUpVeJoePerSharePerSec,
        uint256 _speedUpThreshold,
        uint256 _speedUpDuration,
        uint256 _maxCapPct
    ) public initializer {
        __Ownable_init();

        require(address(_joe) != address(0), "VeJoeStaking: unexpected zero address for _joe");
        require(address(_veJoe) != address(0), "VeJoeStaking: unexpected zero address for _veJoe");

        upperLimitVeJoePerSharePerSec = 1e36;
        require(
            _veJoePerSharePerSec <= upperLimitVeJoePerSharePerSec,
            "VeJoeStaking: expected _veJoePerSharePerSec to be <= 1e36"
        );
        require(
            _speedUpVeJoePerSharePerSec <= upperLimitVeJoePerSharePerSec,
            "VeJoeStaking: expected _speedUpVeJoePerSharePerSec to be <= 1e36"
        );

        require(
            _speedUpThreshold != 0 && _speedUpThreshold <= 100,
            "VeJoeStaking: expected _speedUpThreshold to be > 0 and <= 100"
        );

        require(_speedUpDuration <= 365 days, "VeJoeStaking: expected _speedUpDuration to be <= 365 days");

        upperLimitMaxCapPct = 10000000;
        require(
            _maxCapPct != 0 && _maxCapPct <= upperLimitMaxCapPct,
            "VeJoeStaking: expected _maxCapPct to be non-zero and <= 10000000"
        );

        maxCapPct = _maxCapPct;
        speedUpThreshold = _speedUpThreshold;
        speedUpDuration = _speedUpDuration;
        joe = _joe;
        veJoe = _veJoe;
        veJoePerSharePerSec = _veJoePerSharePerSec;
        speedUpVeJoePerSharePerSec = _speedUpVeJoePerSharePerSec;
        lastRewardTimestamp = block.timestamp;
        ACC_VEJOE_PER_SHARE_PRECISION = 1e18;
        VEJOE_PER_SHARE_PER_SEC_PRECISION = 1e18;
    }

    /// @notice Set maxCapPct
    /// @param _maxCapPct The new maxCapPct
    function setMaxCapPct(uint256 _maxCapPct) external onlyOwner {
        require(_maxCapPct > maxCapPct, "VeJoeStaking: expected new _maxCapPct to be greater than existing maxCapPct");
        require(
            _maxCapPct != 0 && _maxCapPct <= upperLimitMaxCapPct,
            "VeJoeStaking: expected new _maxCapPct to be non-zero and <= 10000000"
        );
        maxCapPct = _maxCapPct;
        emit UpdateMaxCapPct(msg.sender, _maxCapPct);
    }

    /// @notice Set veJoePerSharePerSec
    /// @param _veJoePerSharePerSec The new veJoePerSharePerSec
    function setVeJoePerSharePerSec(uint256 _veJoePerSharePerSec) external onlyOwner {
        require(
            _veJoePerSharePerSec <= upperLimitVeJoePerSharePerSec,
            "VeJoeStaking: expected _veJoePerSharePerSec to be <= 1e36"
        );
        updateRewardVars();
        veJoePerSharePerSec = _veJoePerSharePerSec;
        emit UpdateVeJoePerSharePerSec(msg.sender, _veJoePerSharePerSec);
    }

    /// @notice Set speedUpThreshold
    /// @param _speedUpThreshold The new speedUpThreshold
    function setSpeedUpThreshold(uint256 _speedUpThreshold) external onlyOwner {
        require(
            _speedUpThreshold != 0 && _speedUpThreshold <= 100,
            "VeJoeStaking: expected _speedUpThreshold to be > 0 and <= 100"
        );
        speedUpThreshold = _speedUpThreshold;
        emit UpdateSpeedUpThreshold(msg.sender, _speedUpThreshold);
    }

    /// @notice Deposits JOE to start staking for veJOE. Note that any pending veJOE
    /// will also be claimed in the process.
    /// @param _amount The amount of JOE to deposit
    function deposit(uint256 _amount) external {
        require(_amount > 0, "VeJoeStaking: expected deposit amount to be greater than zero");

        updateRewardVars();

        UserInfo storage userInfo = userInfos[msg.sender];

        if (_getUserHasNonZeroBalance(msg.sender)) {
            // Transfer to the user their pending veJOE before updating their UserInfo
            _claim();

            // We need to update user's `lastClaimTimestamp` to now to prevent
            // passive veJOE accrual if user hit their max cap.
            userInfo.lastClaimTimestamp = block.timestamp;

            uint256 userStakedJoe = userInfo.balance;

            // User is eligible for speed up benefits if `_amount` is at least
            // `speedUpThreshold / 100 * userStakedJoe`
            if (_amount.mul(100) >= speedUpThreshold.mul(userStakedJoe)) {
                userInfo.speedUpEndTimestamp = block.timestamp.add(speedUpDuration);
            }
        } else {
            // If user is depositing with zero balance, they will automatically
            // receive speed up benefits
            userInfo.speedUpEndTimestamp = block.timestamp.add(speedUpDuration);
            userInfo.lastClaimTimestamp = block.timestamp;
        }

        userInfo.balance = userInfo.balance.add(_amount);
        userInfo.rewardDebt = accVeJoePerShare.mul(userInfo.balance).div(ACC_VEJOE_PER_SHARE_PRECISION);

        joe.safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _amount);
    }

    /// @notice Withdraw staked JOE. Note that unstaking any amount of JOE means you will
    /// lose all of your current veJOE.
    /// @param _amount The amount of JOE to unstake
    function withdraw(uint256 _amount) external {
        require(_amount > 0, "VeJoeStaking: expected withdraw amount to be greater than zero");

        UserInfo storage userInfo = userInfos[msg.sender];

        require(
            userInfo.balance >= _amount,
            "VeJoeStaking: cannot withdraw greater amount of JOE than currently staked"
        );
        updateRewardVars();

        // Note that we don't need to claim as the user's veJOE balance will be reset to 0
        userInfo.balance = userInfo.balance.sub(_amount);
        userInfo.rewardDebt = accVeJoePerShare.mul(userInfo.balance).div(ACC_VEJOE_PER_SHARE_PRECISION);
        userInfo.lastClaimTimestamp = block.timestamp;
        userInfo.speedUpEndTimestamp = 0;

        // Burn the user's current veJOE balance
        veJoe.burnFrom(msg.sender, veJoe.balanceOf(msg.sender));

        // Send user their requested amount of staked JOE
        joe.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /// @notice Claim any pending veJOE
    function claim() external {
        require(_getUserHasNonZeroBalance(msg.sender), "VeJoeStaking: cannot claim veJOE when no JOE is staked");
        updateRewardVars();
        _claim();
    }

    /// @notice Get the pending amount of veJOE for a given user
    /// @param _user The user to lookup
    /// @return The number of pending veJOE tokens for `_user`
    function getPendingVeJoe(address _user) public view returns (uint256) {
        if (!_getUserHasNonZeroBalance(_user)) {
            return 0;
        }

        UserInfo memory user = userInfos[_user];

        // Calculate amount of pending base veJOE
        uint256 _accVeJoePerShare = accVeJoePerShare;
        uint256 secondsElapsed = block.timestamp.sub(lastRewardTimestamp);
        if (secondsElapsed > 0) {
            _accVeJoePerShare = _accVeJoePerShare.add(
                secondsElapsed.mul(veJoePerSharePerSec).mul(ACC_VEJOE_PER_SHARE_PRECISION).div(
                    VEJOE_PER_SHARE_PER_SEC_PRECISION
                )
            );
        }
        uint256 pendingBaseVeJoe = _accVeJoePerShare.mul(user.balance).div(ACC_VEJOE_PER_SHARE_PRECISION).sub(
            user.rewardDebt
        );

        // Calculate amount of pending speed up veJOE
        uint256 pendingSpeedUpVeJoe;
        if (user.speedUpEndTimestamp != 0) {
            uint256 speedUpCeilingTimestamp = block.timestamp > user.speedUpEndTimestamp
                ? user.speedUpEndTimestamp
                : block.timestamp;
            uint256 speedUpSecondsElapsed = speedUpCeilingTimestamp.sub(user.lastClaimTimestamp);
            uint256 speedUpAccVeJoePerShare = speedUpSecondsElapsed.mul(speedUpVeJoePerSharePerSec);
            pendingSpeedUpVeJoe = speedUpAccVeJoePerShare.mul(user.balance).div(VEJOE_PER_SHARE_PER_SEC_PRECISION);
        }

        uint256 pendingVeJoe = pendingBaseVeJoe.add(pendingSpeedUpVeJoe);

        // Get the user's current veJOE balance
        uint256 userVeJoeBalance = veJoe.balanceOf(_user);

        // This is the user's max veJOE cap multiplied by 100
        uint256 scaledUserMaxVeJoeCap = user.balance.mul(maxCapPct);

        if (userVeJoeBalance.mul(100) >= scaledUserMaxVeJoeCap) {
            // User already holds maximum amount of veJOE so there is no pending veJOE
            return 0;
        } else if (userVeJoeBalance.add(pendingVeJoe).mul(100) > scaledUserMaxVeJoeCap) {
            return scaledUserMaxVeJoeCap.sub(userVeJoeBalance.mul(100)).div(100);
        } else {
            return pendingVeJoe;
        }
    }

    /// @notice Update reward variables
    function updateRewardVars() public {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        if (joe.balanceOf(address(this)) == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 secondsElapsed = block.timestamp.sub(lastRewardTimestamp);
        accVeJoePerShare = accVeJoePerShare.add(
            secondsElapsed.mul(veJoePerSharePerSec).mul(ACC_VEJOE_PER_SHARE_PRECISION).div(
                VEJOE_PER_SHARE_PER_SEC_PRECISION
            )
        );
        lastRewardTimestamp = block.timestamp;

        emit UpdateRewardVars(lastRewardTimestamp, accVeJoePerShare);
    }

    /// @notice Checks to see if a given user currently has staked JOE
    /// @param _user The user address to check
    /// @return Whether `_user` currently has staked JOE
    function _getUserHasNonZeroBalance(address _user) private view returns (bool) {
        return userInfos[_user].balance > 0;
    }

    /// @dev Helper to claim any pending veJOE
    function _claim() private {
        uint256 veJoeToClaim = getPendingVeJoe(msg.sender);

        UserInfo storage userInfo = userInfos[msg.sender];

        userInfo.rewardDebt = accVeJoePerShare.mul(userInfo.balance).div(ACC_VEJOE_PER_SHARE_PRECISION);

        // If user's speed up period has ended, reset `speedUpEndTimestamp` to 0
        if (userInfo.speedUpEndTimestamp != 0 && block.timestamp >= userInfo.speedUpEndTimestamp) {
            userInfo.speedUpEndTimestamp = 0;
        }

        if (veJoeToClaim > 0) {
            userInfo.lastClaimTimestamp = block.timestamp;

            veJoe.mint(msg.sender, veJoeToClaim);
            emit Claim(msg.sender, veJoeToClaim);
        }
    }
}
