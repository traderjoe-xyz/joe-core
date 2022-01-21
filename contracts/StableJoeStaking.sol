// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

/**
 * @title Stable JOE Staking
 * @author Trader Joe
 * @notice StableJoeStaking is a contract that allows users to deposit JOE and receive stablecoins sent by JoeMakerV4's daily
 * harvests. Users deposit JOE and receive a share of what has been sent by JoeMakerV4 based on their participation
 * of the total deposited JOE.
 *
 * Every day at 00:00 we update `tokenPerSecScaled` to distribute today's reward, `accruedRewards`.
 * When calling updatePool, it distributes the remaining time of previous day with the previous rewards.
 * After what, it updates `tokenPerSecScaled` and distributes the tokens according to the elapsed time, if elapsed time
 * is bigger than 1 day, then we only distribute 1 day worth of rewards as it's calculated to be be only for one day.
 */
contract StableJoeStaking is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Info of each user
    struct UserInfo {
        /// @notice How many JOE tokens user has provided
        uint256 amount;
        /// @notice The sum of rewards already paid to this account. See explanation below
        uint256 rewardDebt;
        /**
         * @notice We do some fancy math here. Basically, any point in time, the amount of JOEs
         * entitled to a user but is pending to be distributed is:
         *
         *   pending reward = (user.amount * accTokenPerShare) - user.rewardDebt
         *
         * Whenever a user deposits or withdraws JOE. Here's what happens:
         *   1. accTokenPerShare (and `lastRewardBalance`) gets updated
         *   2. User receives the pending reward sent to his/her address
         *   3. User's `amount` gets updated
         *   4. User's `rewardDebt` gets updated
         */
    }

    /// @notice JOE token that will be deposited to enter sJOE
    IERC20Upgradeable public joe;

    /// @notice The reward token sent by JoeMakerV4
    IERC20Upgradeable public rewardToken;
    /// @notice last timestamp someone called update and rewards were distributed
    uint256 public lastRewardTimestamp;

    /// @notice The number of token distributed to users inside sJOE, scaled to `PRECISION`
    uint256 private tokensPerSecScaled;
    /// @dev We update `tokensPerSecScaled` 1 day after `lastDailyRewardTimestamp`
    uint256 public lastDailyRewardTimestamp;
    /// @notice Last balance of reward token
    uint256 public lastRewardBalance;

    /// @notice Accumulated Tokens per share, scaled to `PRECISION`. See above
    uint256 public accTokenPerShare;
    /// @notice `PRECISION` of `accTokenPerShare` and `tokensPerSecScaled`
    uint256 public PRECISION;

    /// @notice Info of each user that stakes JOE
    mapping(address => UserInfo) public userInfo;

    /// @notice Emitted when a user deposits its JOE
    event Deposit(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws its JOE
    event Withdraw(address indexed user, uint256 amount);

    /// @notice Emitted when a user emergency withdraws its JOE
    event EmergencyWithdraw(address indexed user, uint256 amount);

    /**
     * @notice Initialize a new StableJoeStaking contract
     * @dev This contract needs to receive an ERC20 `_rewardToken` in order to distribute them
     * (with JoeMakerV4 in our case)
     * @param _rewardToken The address of the ERC20 reward token
     * @param _joe The address of the JOE token
     */
    function initialize(IERC20Upgradeable _rewardToken, IERC20Upgradeable _joe) external initializer {
        __Ownable_init();

        rewardToken = _rewardToken;
        joe = _joe;

        /// @dev Added to be upgrade safe
        lastRewardBalance = _rewardToken.balanceOf(address(this));
        PRECISION = 1e12;
        tokensPerSecScaled = 0;
        /// @dev Timestamp of the day rounded to 00:00. according to Euclid's division lemma:
        /// `block.timestamp = nb_of_days * 1 days + second_of_current_day`   where `second_of_current_day < 1 days` and
        ///                                                                         `nb_of_days * 1 days` equals to today's timestamp at 00:00
        ///                 `=> nb_of_days = (block.timestamp - second_of_current_day) / 1 days`
        ///                 `=> nb_of_days = block.timestamp  / 1 days` (because we're doing integer division and `second_of_current_day < 1 days`)
        ///                 `=> nb_of_days * 1 days = block.timestamp / 1 days * 1 days`
        /// this is equivalent to `block.timestamp - (block.timestamp % 1 days)`
        lastDailyRewardTimestamp = (block.timestamp / 1 days) * 1 days;
    }

    /**
     * @notice Deposit JOE to sJOE for reward token allocation
     * @param _amount The amount of JOE to deposit
     */
    function deposit(uint256 _amount) external {
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(accTokenPerShare).div(PRECISION).sub(user.rewardDebt);
            safeTokenTransfer(msg.sender, pending);
        }
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(accTokenPerShare).div(PRECISION);

        joe.safeTransferFrom(address(msg.sender), address(this), _amount);
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice Return the number of tokens sent to users per sec
     * @return uint256 The amount of tokens distributed per seconds
     */
    function tokensPerSec() external view returns (uint256) {
        return tokensPerSecScaled.div(PRECISION);
    }

    /**
     * @notice View function to see pending reward token on frontend
     * @param _user The address of the user
     * @return `_user`'s pending reward token
     */
    function pendingTokens(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];

        uint256 totalJoe = joe.balanceOf(address(this));
        uint256 _accTokenPerShare = accTokenPerShare;
        uint256 _lastRewardTimestamp = lastRewardTimestamp;
        uint256 _lastDailyRewardTimestamp = lastDailyRewardTimestamp;
        uint256 _tokensPerSecScaled = tokensPerSecScaled;
        uint256 _lastRewardBalance = lastRewardBalance;

        uint256 _multiplier;
        uint256 _tokenReward;
        // Update values to be accurate with today's buyback
        if (block.timestamp > _lastDailyRewardTimestamp + 1 days) {
            // Remaining time of the previous buyback
            _multiplier = 1 days - (_lastRewardTimestamp % 1 days);

            _tokenReward = _multiplier.mul(_tokensPerSecScaled);

            // Now we update the values for today's buyback
            _lastRewardTimestamp = _lastDailyRewardTimestamp + 1 days;
            // Get the current day at 00:00:00
            // `_lastRewardTimestamp` and `_lastDailyRewardTimestamp` can be different if
            // `block.timestamp > _lastDailyRewardTimestamp + 2 days`, i.e. if `updatePool` isn't called
            // for at least an entire day
            _lastDailyRewardTimestamp = (block.timestamp / 1 days) * 1 days;

            // Get today's buyback amount
            uint256 _accruedRewards = rewardToken.balanceOf(address(this)).sub(_lastRewardBalance);
            _lastRewardBalance = _lastRewardBalance.add(_accruedRewards);

            // Distribute today's buyback over 1 day
            _tokensPerSecScaled = _accruedRewards.mul(PRECISION).div(1 days);
        }

        // In case `updatePool` isn't called at least once per day, we need to make sure user receives only one day
        // worth of token
        if (block.timestamp > lastRewardTimestamp + 1 days) {
            _multiplier = 1 days;
        } else {
            _multiplier = block.timestamp - _lastRewardTimestamp;
        }

        _tokenReward = _tokenReward.add(_multiplier.mul(_tokensPerSecScaled));

        _accTokenPerShare = _accTokenPerShare.add(_tokenReward.div(totalJoe));
        return user.amount.mul(_accTokenPerShare).div(PRECISION).sub(user.rewardDebt);
    }

    /**
     * @notice Withdraw JOE from sJOE and harvest the rewards
     * @param _amount The amount of JOE to withdraw
     */
    function withdraw(uint256 _amount) external {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "StableJoeStaking: withdraw amount exceeds balance");

        updatePool();
        uint256 pending = user.amount.mul(accTokenPerShare).div(PRECISION).sub(user.rewardDebt);

        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(accTokenPerShare).div(PRECISION);

        safeTokenTransfer(msg.sender, pending);
        joe.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @notice Withdraw without caring about rewards. EMERGENCY ONLY
     */
    function emergencyWithdraw() external {
        UserInfo storage user = userInfo[msg.sender];

        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        joe.safeTransfer(address(msg.sender), _amount);
        emit EmergencyWithdraw(msg.sender, _amount);
    }

    /**
     * @notice Update reward variables to be up-to-date
     * @dev Needs to be called before any deposit or withdrawal
     */
    function updatePool() public {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        uint256 totalJoe = joe.balanceOf(address(this));
        if (totalJoe == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 multiplier;
        uint256 tokenReward;
        // Update values to be accurate with today's buyback
        if (block.timestamp > lastDailyRewardTimestamp + 1 days) {
            // Remaining time of the previous buyback
            multiplier = 1 days - (lastRewardTimestamp % 1 days);

            tokenReward = multiplier.mul(tokensPerSecScaled);

            // Now we update the values for today's buyback
            lastRewardTimestamp = lastDailyRewardTimestamp + 1 days;
            // Get the current day at 00:00:00
            // `_lastRewardTimestamp` and `_lastDailyRewardTimestamp` can be different if
            // `block.timestamp > _lastDailyRewardTimestamp + 2 days`, i.e. if `updatePool` isn't called
            // for at least an entire day
            lastDailyRewardTimestamp = (block.timestamp / 1 days) * 1 days;

            // Get today's buyback amount
            uint256 accruedRewards = rewardToken.balanceOf(address(this)).sub(lastRewardBalance);
            lastRewardBalance = lastRewardBalance.add(accruedRewards);

            // Distribute today's buyback over 1 day
            tokensPerSecScaled = accruedRewards.mul(PRECISION).div(1 days);
        }

        // In case `updatePool` isn't called at least once per day, we need to make sure user receives only one day
        // worth of token
        if (block.timestamp > lastRewardTimestamp + 1 days) {
            tokenReward = tokenReward.add(uint256(1 days).mul(tokensPerSecScaled));
            tokensPerSecScaled = 0;
        } else {
            multiplier = block.timestamp - lastRewardTimestamp;
            tokenReward = tokenReward.add(multiplier.mul(tokensPerSecScaled));
        }

        accTokenPerShare = accTokenPerShare.add(tokenReward.div(totalJoe));
        lastRewardTimestamp = block.timestamp;
    }

    /**
     * @notice Safe token transfer function, just in case if rounding error
     * causes pool to not have enough reward tokens
     * @param _to The address that will receive `_amount` `rewardToken`
     * @param _amount The amount to send to `_to`
     */
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 rewardTokenBal = rewardToken.balanceOf(address(this));
        if (_amount > rewardTokenBal) {
            lastRewardBalance = lastRewardBalance.sub(rewardTokenBal);
            rewardToken.transfer(_to, rewardTokenBal);
        } else {
            lastRewardBalance = lastRewardBalance.sub(_amount);
            rewardToken.transfer(_to, _amount);
        }
    }
}
