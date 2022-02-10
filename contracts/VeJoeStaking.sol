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

    struct UserInfo {
        uint256 balance; // Amount of JOE currently staked by user
        uint256 lastRewardTimestamp; // Timestamp of last non-zero veJOE claim, or time of first
        // deposit if user has not claimed any veJOE yet
        uint256 boostEndTimestamp; // Timestamp of when user stops receiving boost benefits.
        // Note that this will be reset to 0 after the end of a boost
    }

    IERC20Upgradeable public joe;
    VeJoeToken public veJoe;

    /// @notice The maximum ratio of veJOE to staked JOE
    /// For example, if user has `n` JOE staked, they can own a maximum of `n * maxCap` veJOE.
    uint256 public maxCap;

    /// @notice Rate of veJOE generated per sec per JOE staked, in parts per 1e18
    uint256 public baseGenerationRate;

    /// @notice Boosted rate of veJOE generated per sec per JOE staked, in parts per 1e18
    uint256 public boostedGenerationRate;

    /// @notice Precision of `baseGenerationRate` and `boostedGenerationRate`
    uint256 public PRECISION;

    /// @notice Percentage of user's current staked JOE user has to deposit in order to start
    /// receiving boosted benefits, in parts per 100.
    /// @dev Specifically, user has to deposit at least `boostedThreshold/100 * userStakedJoe` JOE.
    /// The only exception is the user will also receive boosted benefits if it's their first
    /// time staking.
    uint256 public boostedThreshold;

    /// @notice The length of time a user receives boosted benefits
    uint256 public boostedDuration;

    mapping(address => UserInfo) public userInfos;

    event Claim(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event UpdateBaseGenerationRate(address indexed user, uint256 baseGenerationRate);
    event UpdateBoostedDuration(address indexed user, uint256 boostedDuration);
    event UpdateBoostedGenerationRate(address indexed user, uint256 boostedGenerationRate);
    event UpdateBoostedThreshold(address indexed user, uint256 boostedThreshold);
    event UpdateMaxCap(address indexed user, uint256 maxCap);
    event Withdraw(address indexed user, uint256 amount);

    /// @notice Initialize with needed parameters
    /// @param _joe Address of the JOE token contract
    /// @param _veJoe Address of the veJOE token contract
    /// @param _baseGenerationRate Rate of veJOE generated per sec per JOE staked
    /// @param _boostedGenerationRate Boosted rate of veJOE generated per sec per JOE staked
    /// @param _boostedThreshold Percentage of total staked JOE user has to deposit to be boosted
    /// @param _boostedDuration Length of time a user receives boosted benefits
    function initialize(
        IERC20Upgradeable _joe,
        VeJoeToken _veJoe,
        uint256 _baseGenerationRate,
        uint256 _boostedGenerationRate,
        uint256 _boostedThreshold,
        uint256 _boostedDuration,
        uint256 _maxCap
    ) public initializer {
        require(address(_joe) != address(0), "VeJoeStaking: unexpected zero address for _joe");
        require(address(_veJoe) != address(0), "VeJoeStaking: unexpected zero address for _veJoe");
        require(
            _boostedGenerationRate > _baseGenerationRate,
            "VeJoeStaking: expected _boostedGenerationRate to be greater than _baseGenerationRate"
        );
        require(_boostedThreshold <= 100, "VeJoeStaking: expected _boostedThreshold to be less than or equal to 100");
        // TODO: Align on what the upper limit of maxCap should be
        require(
            _maxCap > 0 && _maxCap <= 100000,
            "VeJoeStaking: expected new _maxCap to be greater than 0 and leq to 100000"
        );

        __Ownable_init();

        maxCap = _maxCap;
        joe = _joe;
        veJoe = _veJoe;
        baseGenerationRate = _baseGenerationRate;
        boostedGenerationRate = _boostedGenerationRate;
        boostedThreshold = _boostedThreshold;
        // TODO: Align on what the upper limit of boostedDuration should be and add require check
        boostedDuration = _boostedDuration;
        PRECISION = 1e18;
    }

    /// @notice Set maxCap
    /// @param _maxCap The new maxCap
    function setMaxCap(uint256 _maxCap) external onlyOwner {
        require(_maxCap > maxCap, "VeJoeStaking: expected new _maxCap to be greater than existing maxCap");
        // TODO: Align on what the upper limit of maxCap should be
        require(
            _maxCap > 0 && _maxCap <= 100000,
            "VeJoeStaking: expected new _maxCap to be greater than 0 and leq to 100000"
        );
        maxCap = _maxCap;
        emit UpdateMaxCap(msg.sender, _maxCap);
    }

    /// @notice Set baseGenerationRate
    /// @param _baseGenerationRate The new baseGenerationRate
    function setBaseGenerationRate(uint256 _baseGenerationRate) external onlyOwner {
        require(
            _baseGenerationRate < boostedGenerationRate,
            "VeJoeStaking: expected new _baseGenerationRate to be less than boostedGenerationRate"
        );
        baseGenerationRate = _baseGenerationRate;
        emit UpdateBaseGenerationRate(msg.sender, _baseGenerationRate);
    }

    /// @notice Set boostedGenerationRate
    /// @param _boostedGenerationRate The new boostedGenerationRate
    function setBoostedGenerationRate(uint256 _boostedGenerationRate) external onlyOwner {
        require(
            _boostedGenerationRate > baseGenerationRate,
            "VeJoeStaking: expected new _boostedGenerationRate to be greater than baseGenerationRate"
        );
        boostedGenerationRate = _boostedGenerationRate;
        emit UpdateBoostedGenerationRate(msg.sender, _boostedGenerationRate);
    }

    /// @notice Set boostedThreshold
    /// @param _boostedThreshold The new boostedThreshold
    function setBoostedThreshold(uint256 _boostedThreshold) external onlyOwner {
        require(
            _boostedThreshold <= 100,
            "VeJoeStaking: expected new _boostedThreshold to be less than or equal to 100"
        );
        boostedThreshold = _boostedThreshold;
        emit UpdateBoostedThreshold(msg.sender, _boostedThreshold);
    }

    /// @notice Set boostedDuration
    /// @param _boostedDuration The new boostedDuration
    function setBoostedDuration(uint256 _boostedDuration) external onlyOwner {
        boostedDuration = _boostedDuration;
        emit UpdateBoostedDuration(msg.sender, _boostedDuration);
    }

    /// @notice Deposits JOE to start staking for veJOE. Note that any pending veJOE
    /// will also be claimed in the process.
    /// @param _amount The amount of JOE to deposit
    function deposit(uint256 _amount) external {
        require(_amount > 0, "VeJoeStaking: expected deposit amount to be greater than zero");

        UserInfo storage userInfo = userInfos[msg.sender];

        if (_getUserHasNonZeroBalance(msg.sender)) {
            // If user already has staked JOE, we first send them any pending veJOE
            _claim();

            uint256 userStakedJoe = userInfo.balance;

            userInfo.balance = userStakedJoe.add(_amount);

            // User is eligible for boosted benefits if and only if all of the following are true:
            // - User is not already currently receiving boosted benefits
            // - `_amount` is at least `boostedThreshold / 100 * userStakedJoe`
            if (userInfo.boostEndTimestamp == 0 && _amount.mul(100) >= boostedThreshold.mul(userStakedJoe)) {
                userInfo.boostEndTimestamp = block.timestamp.add(boostedDuration);
            }
        } else {
            // If the user's `lastRewardTimestamp` is 0, i.e. if this is the user's first time staking,
            // then they will receive boosted benefits.
            // Note that it is important we perform this check **before** we update the user's `lastRewardTimestamp`
            // down below.
            if (userInfo.lastRewardTimestamp == 0) {
                userInfo.boostEndTimestamp = block.timestamp.add(boostedDuration);
            }
            userInfo.balance = _amount;
            userInfo.lastRewardTimestamp = block.timestamp;
        }

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

        userInfo.balance = userInfo.balance.sub(_amount);
        userInfo.lastRewardTimestamp = block.timestamp;
        userInfo.boostEndTimestamp = 0;

        // Burn the user's current veJOE balance
        uint256 userVeJoeBalance = veJoe.balanceOf(msg.sender);
        veJoe.burnFrom(msg.sender, userVeJoeBalance);

        // Send user their requested amount of staked JOE
        joe.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /// @notice Claim any pending veJOE
    function claim() external {
        require(_getUserHasNonZeroBalance(msg.sender), "VeJoeStaking: cannot claim veJOE when no JOE is staked");
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

        uint256 secondsElapsed = block.timestamp.sub(user.lastRewardTimestamp);
        if (secondsElapsed == 0) {
            return 0;
        }

        // Calculate amount of pending veJOE based on:
        // 1. Seconds elapsed since last reward timestamp
        // 2. Generation rate that the user is receiving
        // 3. Current amount of user's staked JOE
        uint256 pendingVeJoe;

        if (block.timestamp <= user.boostEndTimestamp) {
            // If the current timestamp is less than or equal to the user's `boostEndTimestamp`,
            // that means the user is currently receiving boosted benefits so they should receive
            // `boostedGenerationRate`.
            uint256 accVeJoePerJoe = secondsElapsed.mul(boostedGenerationRate);
            pendingVeJoe = accVeJoePerJoe.mul(user.balance).div(PRECISION);
        } else {
            if (user.boostEndTimestamp != 0) {
                // If `user.boostEndTimestamp != 0` then, we know for certain that
                // `user.boostEndTimestamp >= user.lastRewardTimestamp`.
                // Proof by contradiction:
                // 1. Assume that `user.boostEndTimestamp != 0` and
                //    `user.boostEndTimestamp < user.lastRewardTimestamp`.
                // 2. That means that at time `user.lastRewardTimestamp`, the user claimed
                //    some veJOE. Furthermore, we know that anytime a user claims some veJOE,
                //    if the current timestamp is greater than or equal to `user.boostEndTimestamp`,
                //    we will update `user.boostEndTimestamp` to be `0` (see `_claim` method).
                // 3. This means that `user.boostEndTimestamp` should be `0` but that contradicts our
                //    assumption that `user.boostEndTimestamp != 0`
                // QED.
                // With this, we now know `0 < user.lastRewardTimestamp <= user.boostEndTimestamp < block.timestamp`,
                // which will allow us to perform the following logic safely.

                // If the `block.timestamp > user.boostEndTimestamp` and `boostEndTimestamp != 0`,
                // that means the user's boosted benefits ended sometime between their `lastRewardTimestamp`
                // and now.
                // In this case, we need to properly provide them the boosted generation rate for
                // those `boostEndTimestamp - lastRewardTimestamp` seconds.
                uint256 boostedTimeElapsed = user.boostEndTimestamp.sub(user.lastRewardTimestamp);
                uint256 boostedAccVeJoePerJoe = boostedTimeElapsed.mul(boostedGenerationRate);
                uint256 boostedPendingVeJoe = boostedAccVeJoePerJoe.mul(user.balance);

                uint256 baseTimeElapsed = block.timestamp.sub(user.boostEndTimestamp);
                uint256 baseAccVeJoePerVeJoe = baseTimeElapsed.mul(baseGenerationRate);
                uint256 basePendingVeJoe = baseAccVeJoePerVeJoe.mul(user.balance);

                pendingVeJoe = boostedPendingVeJoe.add(basePendingVeJoe).div(PRECISION);
            } else {
                // In this case, the user is simply generating veJOE at `baseGenerationRate` for
                // the duration of `secondsElapsed`.
                uint256 accVeJoePerJoe = secondsElapsed.mul(baseGenerationRate);
                pendingVeJoe = accVeJoePerJoe.mul(user.balance).div(PRECISION);
            }
        }

        // Get the user's current veJOE balance and maximum veJOE they can hold
        uint256 userVeJoeBalance = veJoe.balanceOf(_user);
        uint256 userMaxVeJoeCap = user.balance.mul(maxCap);

        if (userVeJoeBalance < userMaxVeJoeCap) {
            if (userVeJoeBalance.add(pendingVeJoe) > userMaxVeJoeCap) {
                return userMaxVeJoeCap.sub(userVeJoeBalance);
            } else {
                return pendingVeJoe;
            }
        } else {
            // User already holds maximum amount of veJOE so there is no pending veJOE
            return 0;
        }
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

        if (veJoeToClaim > 0) {
            UserInfo storage userInfo = userInfos[msg.sender];

            // Update user's last reward timestamp
            userInfo.lastRewardTimestamp = block.timestamp;

            // If user's boost period has ended, reset `boostEndTimestamp` to 0
            if (userInfo.boostEndTimestamp != 0 && block.timestamp >= userInfo.boostEndTimestamp) {
                userInfo.boostEndTimestamp = 0;
            }

            veJoe.mint(msg.sender, veJoeToClaim);
            emit Claim(msg.sender, veJoeToClaim);
        }
    }
}
