// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title Stable JOE Staking
 * @author Trader Joe
 * @notice StableJoeStaking is a contract that allows to deposit JOE and receives stable coin sent by JoeMakerV4's daily
 * harvests. Users deposit JOE and receive a share of what has been sent by JoeMakerV4 based on their participation
 * of the total deposited JOE
 */
contract StableJoeStaking is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Info of each user
    struct UserInfo {
        uint256 amount; /// @notice How many LP rewardTokens the user has provided
        uint256 rewardDebt; /// @notice The sum of rewards already paid to this account. See explanation below
        /**
         * @notice We do some fancy math here. Basically, any point in time, the amount of JOEs
         * entitled to a user but is pending to be distributed is:
         *
         *   pending reward = (user.amount * accTokenPerShare) - user.rewardDebt
         *
         * Whenever a user deposits or withdraws JOE. Here's what happens:
         *   1. accTokenPerShare (and `lastTokenBalance`) gets updated
         *   2. User receives the pending reward sent to his/her address
         *   3. User's `amount` gets updated
         *   4. User's `rewardDebt` gets updated
         */
    }

    /// @notice JOE token that will be deposited to enter sJOE.
    IERC20Upgradeable public joe;

    /// @notice The reward token sent by JoeMakerV4
    IERC20Upgradeable public rewardToken;
    uint256 public lastRewardTimestamp;

    uint256 private tokenPerSecScaled;
    /// @dev We update tokenPerSec after 1 day after lastDailyFeeTimestamp
    uint256 public lastDailyFeeTimestamp;
    /// @notice Last balance of reward token
    uint256 public lastTokenBalance;
    uint256 public reserves;

    /// @notice Accumulated Tokens per share, times PRECISION. See above
    uint256 public accTokenPerShare;
    /// @notice PRECISION of accTokenPerShare
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
     * @param _rewardToken The address of the ERC-20 reward token
     * @param _joe The address of the JOE token
     */
    function initialize(IERC20Upgradeable _rewardToken, IERC20Upgradeable _joe) external initializer {
        __Ownable_init();

        rewardToken = _rewardToken;
        joe = _joe;

        lastTokenBalance = _rewardToken.balanceOf(address(this)); /// @dev Added to be upgrade safe
        PRECISION = 1e12; /// @dev initialized here to be upgrade safe
        lastDailyFeeTimestamp = (block.timestamp / 1 days) * 1 days;
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
     * @notice return the token per sec.
     */
    function tokenPerSec() external view returns (uint256) {
        return tokenPerSecScaled.div(PRECISION);
    }

    /**
     * @notice View function to see pending reward token on frontend
     * @param _user The address of the user
     * @return `_user`'s pending reward token
     */
    function pendingToken(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 lpSupply = joe.balanceOf(address(this));
        uint256 _accTokenPerShare = accTokenPerShare;
        uint256 _multiplier;
        uint256 _tokenReward;
        uint256 _lastRewardTimestamp = lastRewardTimestamp;
        uint256 _lastDailyFeeTimestamp = lastDailyFeeTimestamp;
        uint256 _tokenPerSecScaled = tokenPerSecScaled;
        uint256 _lastTokenBalance = lastTokenBalance;
        if (block.timestamp > _lastDailyFeeTimestamp + 1 days) {
            _multiplier = 1 days - (_lastRewardTimestamp % 1 days);

            _tokenReward = _multiplier.mul(_tokenPerSecScaled);

            _lastRewardTimestamp = _lastDailyFeeTimestamp + 1 days;
            _lastDailyFeeTimestamp = (block.timestamp / 1 days) * 1 days;

            uint256 _accruedFee = rewardToken.balanceOf(address(this)).sub(_lastTokenBalance);
            _lastTokenBalance = _lastTokenBalance.add(_accruedFee);

            _tokenPerSecScaled = _accruedFee.mul(PRECISION).div(1 days);
        }

        if (block.timestamp > lastRewardTimestamp + 1 days) {
            _multiplier = 1 days;
        } else {
            _multiplier = block.timestamp - _lastRewardTimestamp;
        }

        _tokenReward = _tokenReward.add(_multiplier.mul(_tokenPerSecScaled));

        _accTokenPerShare = _accTokenPerShare.add(_tokenReward.div(lpSupply));
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

        uint256 lpSupply = joe.balanceOf(address(this));
        if (lpSupply == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 multiplier;
        uint256 tokenReward;
        // each day we update token per sec
        if (block.timestamp > lastDailyFeeTimestamp + 1 days) {
            // remaining time of the previous day
            multiplier = 1 days - (lastRewardTimestamp % 1 days);

            tokenReward = multiplier.mul(tokenPerSecScaled);

            // now we update the values for the new day
            lastRewardTimestamp = lastDailyFeeTimestamp + 1 days;
            lastDailyFeeTimestamp = (block.timestamp / 1 days) * 1 days;

            // tokens sent to the contract are added to accruedFee and redistributed during the next 24h
            uint256 accruedFee = rewardToken.balanceOf(address(this)).sub(lastTokenBalance);
            lastTokenBalance = lastTokenBalance.add(accruedFee);

            tokenPerSecScaled = accruedFee.mul(PRECISION).div(1 days);
        }

        // in case update isn't called in more than 2 days, we need to make sure user receive only one day
        // worth of token
        if (block.timestamp > lastRewardTimestamp + 1 days) {
            tokenReward = tokenReward.add(uint256(1 days).mul(tokenPerSecScaled));
            tokenPerSecScaled = 0;
        } else {
            multiplier = block.timestamp - lastRewardTimestamp;
            tokenReward = tokenReward.add(multiplier.mul(tokenPerSecScaled));
        }

        accTokenPerShare = accTokenPerShare.add(tokenReward.div(lpSupply));
        lastRewardTimestamp = block.timestamp;
    }

    /**
     * @notice Safe Token Transfer function, just in case if rounding error
     * causes pool To not have enough reward tokens
     * @param _to The address that will receive `_amount` `rewardToken`
     * @param _amount The amount to send to `_to`
     */
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 rewardTokenBal = rewardToken.balanceOf(address(this));
        if (_amount > rewardTokenBal) {
            rewardToken.transfer(_to, rewardTokenBal);
            lastTokenBalance = lastTokenBalance.sub(rewardTokenBal);
        } else {
            rewardToken.transfer(_to, _amount);
            lastTokenBalance = lastTokenBalance.sub(_amount);
        }
    }
}
