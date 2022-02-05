// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "./openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./VeJoeToken.sol";

/// @title Vote Escrow Joe Staking
/// @author Trader Joe
/// @notice Stake JOE to earn veJOE, which you can use to earn higher farm yields and gain
/// voting power. Note that unstaking any amount of JOE will burn all of your existing veJOE.
contract VeJoeStaking is Initializable, OwnableUpgradeable {
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

    /// @notice Rate of veJOE generated per sec per JOE staked
    uint256 public baseGenerationRate;

    /// @notice Boosted rate of veJOE generated per sec per JOE staked
    uint256 public boostedGenerationRate;

    /// @notice Percentage of total staked JOE user has to deposit in order to start
    /// receiving boosted benefits, in parts per 100.
    /// @dev Specifically, user has to deposit at least `boostedThreshold/100 * totalStakedJoe` JOE.
    /// The only exception is the user will also receive boosted benefits if its their first
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
        uint256 _boostedDuration
    ) public initializer {
        require(address(_joe) != address(0), "VeJoeStaking: unexpected zero address for _joe");
        require(address(_veJoe) != address(0), "VeJoeStaking: unexpected zero address for _veJoe");
        require(
            _boostedGenerationRate > _baseGenerationRate,
            "VeJoeStaking: expected _boostedGenerationRate to be greater than _baseGenerationRate"
        );
        require(_boostedThreshold <= 100, "VeJoeStaking: expected _boostedThreshold to be less than or equal to 100");

        __Ownable_init();

        maxCap = 100;
        joe = _joe;
        veJoe = _veJoe;
        baseGenerationRate = _baseGenerationRate;
        boostedGenerationRate = _boostedGenerationRate;
        boostedThreshold = _boostedThreshold;
        // TODO: Align on what the upper limit of boostedDuration should be and add require check
        boostedDuration = _boostedDuration;
    }

    /// @notice Set maxCap
    /// @param _maxCap the new maxCap
    function setMaxCap(uint256 _maxCap) external onlyOwner {
        // TODO: Align on what the upper limit of maxCap should be
        require(
            _maxCap > 0 && _maxCap <= 100000,
            "VeJoeStaking: expected new _maxCap to be greater than 0 and leq to 100000"
        );
        maxCap = _maxCap;
        emit UpdateMaxCap(msg.sender, _maxCap);
    }

    /// @notice Set baseGenerationRate
    /// @param _baseGenerationRate the new baseGenerationRate
    function setBaseGenerationRate(uint256 _baseGenerationRate) external onlyOwner {
        require(
            _baseGenerationRate < boostedGenerationRate,
            "VeJoeStaking: expected new _baseGenerationRate to be less than boostedGenerationRate"
        );
        baseGenerationRate = _baseGenerationRate;
        emit UpdateBaseGenerationRate(msg.sender, _baseGenerationRate);
    }

    /// @notice Set boostedGenerationRate
    /// @param _boostedGenerationRate the new boostedGenerationRate
    function setBoostedGenerationRate(uint256 _boostedGenerationRate) external onlyOwner {
        require(
            _boostedGenerationRate > baseGenerationRate,
            "VeJoeStaking: expected new _boostedGenerationRate to be greater than baseGenerationRate"
        );
        boostedGenerationRate = _boostedGenerationRate;
        emit UpdateBoostedGenerationRate(msg.sender, _boostedGenerationRate);
    }

    /// @notice Set boostedThreshold
    /// @param _boostedThreshold the new boostedThreshold
    function setBoostedThreshold(uint256 _boostedThreshold) external onlyOwner {
        require(
            _boostedThreshold <= 100,
            "VeJoeStaking: expected new _boostedThreshold to be less than or equal to 100"
        );
        boostedThreshold = _boostedThreshold;
        emit UpdateBoostedThreshold(msg.sender, _boostedThreshold);
    }

    /// @notice Set boostedDuration
    /// @param _boostedDuration the new boostedDuration
    function setBoostedDuration(uint256 _boostedDuration) external onlyOwner {
        boostedDuration = _boostedDuration;
        emit UpdateBoostedDuration(msg.sender, _boostedDuration);
    }

    /// @notice Deposits JOE to start staking for veJOE. Note that any pending veJOE
    /// will also be claimed in the process.
    /// @param _amount the amount of JOE to deposit
    function deposit(uint256 _amount) external {
        require(_amount > 0, "VeJoeStaking: expected deposit amount to be greater than zero");

        if (getUserHasNonZeroBalance(msg.sender)) {
            // If user already has staked JOE, we first send them any pending veJOE
            _claim();

            uint256 userStakedJoe = userInfos[msg.sender].balance;

            userInfos[msg.sender].balance += _amount;

            // User is eligible for boosted benefits if and only if all of the following are true:
            // 1. User is not already currently receiving boosted benefits
            // 2. `_amount` is at least `boostedThreshold / 100 * userStakedJoe`
            if (userInfos[msg.sender].boostEndTimestamp == 0) {
                if (_amount * 100 >= boostedThreshold * userStakedJoe) {
                    userInfos[msg.sender].boostEndTimestamp = block.timestamp + boostedDuration;
                }
            }
        } else {
            // If the user's `lastRewardTimestamp` is 0, i.e. if this is the user's first time staking,
            // then they will receive boosted benefits.
            // Note that it is important we perform this check **before** we update the user's `lastRewardTimestamp`
            // down below.
            if (userInfos[msg.sender].lastRewardTimestamp == 0) {
                userInfos[msg.sender].boostEndTimestamp = block.timestamp + boostedDuration;
            }
            userInfos[msg.sender].balance = _amount;
            userInfos[msg.sender].lastRewardTimestamp = block.timestamp;
        }

        joe.safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _amount);
    }

    /// @notice Withdraw staked JOE. Note that unstaking any amount of JOE means you will
    /// lose all of your current veJOE.
    /// @param _amount the amount of JOE to unstake
    function withdraw(uint256 _amount) external {
        require(_amount > 0, "VeJoeStaking: expected to withdraw non-zero amount of JOE");

        UserInfo storage userInfo = userInfos[msg.sender];

        require(
            userInfo.balance >= _amount,
            "VeJoeStaking: cannot withdraw greater amount of JOE than currently staked"
        );

        userInfo.balance -= _amount;
        userInfo.lastRewardTimestamp = block.timestamp;

        // Burn the user's current veJOE balance
        uint256 userVeJoeBalance = veJoe.balanceOf(msg.sender);
        veJoe.burnFrom(msg.sender, userVeJoeBalance);

        // Send user their requested amount of staked JOE
        joe.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /// @notice Claim any pending veJOE
    function claim() external {
        require(getUserHasNonZeroBalance(msg.sender), "VeJoeStaking: cannot claim any veJOE when no JOE is staked");
        _claim();
    }

    /// @notice Get the pending amount of veJOE for a given user
    /// @param _user The user to lookup
    /// @return The number of pending veJOE tokens for `_user`
    function getPendingVeJoe(address _user) public view returns (uint256) {
        if (!getUserHasNonZeroBalance(_user)) {
            return 0;
        }

        UserInfo memory user = userInfos[_user];

        // Calculate amount of pending veJOE based on:
        // 1. Seconds elapsed since last reward timestamp
        // 2. Generation rate that the user is receiving
        // 3. Current amount of user's staked JOE
        uint256 secondsElapsed = block.timestamp - user.lastRewardTimestamp;
        if (secondsElapsed == 0) {
            return 0;
        }

        // Calculate the generation rate the user should receive (in units of veJOE per sec per JOE).
        // If the current timestamp is less than or equal to the user's `boostEndTimestamp`,
        // that means the user is currently receiving boosted benefits so they should receive
        // `boostedGenerationRate`, otherwise `baseGenerationRate`.
        uint256 generationRate = block.timestamp <= user.boostEndTimestamp ? boostedGenerationRate : baseGenerationRate;

        uint256 accVeJoePerJoe = secondsElapsed * generationRate;

        uint256 pendingVeJoe = accVeJoePerJoe * user.balance;

        // Get the user's current veJOE balance and maximum veJOE they can hold
        uint256 userVeJoeBalance = veJoe.balanceOf(_user);
        uint256 userMaxVeJoeCap = user.balance * maxCap;

        if (userVeJoeBalance < userMaxVeJoeCap) {
            if (userVeJoeBalance + pendingVeJoe > userMaxVeJoeCap) {
                return userMaxVeJoeCap - userVeJoeBalance;
            } else {
                return pendingVeJoe;
            }
        } else {
            // User already holds maximum amount of veJOE so there is no pending veJOE
            return 0;
        }
    }

    /// @notice Checks to see if a given user currently has staked JOE
    /// @param _user the user address to check
    /// @return whether `_user` currently has staked JOE
    function getUserHasNonZeroBalance(address _user) private view returns (bool) {
        return userInfos[_user].balance > 0;
    }

    /// @dev Helper to claim any pending veJOE
    function _claim() private {
        uint256 veJoeToClaim = getPendingVeJoe(msg.sender);

        if (veJoeToClaim > 0) {
            // Update user's last reward timestamp
            userInfos[msg.sender].lastRewardTimestamp = block.timestamp;

            veJoe.mint(msg.sender, veJoeToClaim);
            emit Claim(msg.sender, veJoeToClaim);
        }
    }
}
