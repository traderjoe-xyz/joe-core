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
 * @notice StableJoeStaking is a contract that allows JOE deposits and receives stablecoins sent by JoeMakerV4's daily
 * harvests. Users deposit JOE and receive a share of what has been sent by JoeMakerV4 based on their participation of
 * the total deposited JOE
 * Every time `updatePool(token)` is called, We distribute the balance of that tokens as rewards to users that are
 * currently staking inside this contract.
 */
contract StableJoeStaking is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Info of each user
    struct UserInfo {
        /// @notice How many LP rewardTokens the user has provided
        uint256 amount;
        /// @notice The sum of token rewards already paid to this account. See explanation below
        mapping(address => uint256) rewardDebt;
        /**
         * @notice We do some fancy math here. Basically, any point in time, the amount of JOEs
         * entitled to a user but is pending to be distributed is:
         *
         *   pending reward = (user.amount * accRewardPerShare) - user.rewardDebt[token]
         *
         * Whenever a user deposits or withdraws JOE. Here's what happens:
         *   1. accRewardPerShare (and `lastRewardBalance`) gets updated
         *   2. User receives the pending reward sent to his/her address
         *   3. User's `amount` gets updated
         *   4. User's `rewardDebt[token]` gets updated
         */
    }

    IERC20Upgradeable public joe;

    /// @notice Internal balance of a token, this gets updated on user deposits / withdrawals
    mapping(address => uint256) public internalBalance;
    /// @notice The reward token sent by JoeMakerV4
    address public rewardToken;
    /// @notice Last reward balance of `token`
    mapping(address => uint256) public lastRewardBalance;

    /// @notice The deposit fee, scaled to `PRECISION`
    uint256 public depositFeePercent;

    /// @notice Accumulated `token` rewards per share, scaled to `PRECISION`. See above
    mapping(address => uint256) public accRewardPerShare;
    /// @notice `PRECISION` of `accRewardPerShare`
    uint256 public PRECISION;

    /// @notice Info of each user that stakes JOE
    mapping(address => UserInfo) private userInfo;

    /// @notice Emitted when a user deposits JOE
    event Deposit(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws JOE
    event Withdraw(address indexed user, uint256 amount);

    /// @notice Emitted when a user emergency withdraws its JOE
    event EmergencyWithdraw(address indexed user, uint256 amount);

    /**
     * @notice Initialize a new StableJoeStaking contract
     * @dev This contract needs to receive an ERC20 `_rewardToken` in order to distribute them
     * (with JoeMakerV4 in our case)
     * @param _rewardToken The address of the ERC20 reward token
     * @param _joe The address of the JOE token
     * @param _depositFeePercent The deposit fee percent, scalled to 1e18, e.g. 3% is 3e16
     */
    function initialize(
        address _rewardToken,
        IERC20Upgradeable _joe,
        uint256 _depositFeePercent
    ) external initializer {
        __Ownable_init();

        rewardToken = _rewardToken;
        joe = _joe;

        /// @dev Added to be upgrade safe
        PRECISION = 1e18;
        require(
            _depositFeePercent < PRECISION / 2,
            "StableJoeStaking: max deposit fee can't be greater than 50%"
        );
        depositFeePercent = _depositFeePercent;
    }

    /**
     * @notice Claim reward
     * @param _token The address of the token
     */
    function claimReward(address _token) external {
        UserInfo storage user = userInfo[msg.sender];
        _claimReward(_token, user);
    }

    /**
     * @notice Claim all token reward from the list
     * @param _tokens The list addresses of the tokens
     */
    function claimRewards(address[] memory _tokens) external {
        uint256 len = _tokens.length;
        UserInfo storage user = userInfo[msg.sender];

        for (uint256 i; i < len; i++) {
            _claimReward(_tokens[i], user);
        }
    }

    /**
     * @notice Deposit JOE for reward token allocation
     * @param _amount The amount of JOE to deposit
     */
    function deposit(uint256 _amount) external {
        updatePool(rewardToken);

        UserInfo storage user = userInfo[msg.sender];
        (uint256 previousAmount, uint256 previousDebt) = (
            user.amount,
            user.rewardDebt[rewardToken]
        );

        uint256 fee = (_amount * depositFeePercent) / 1e18;
        uint256 amountMinusFee = _amount.sub(fee);

        user.amount = user.amount.add(amountMinusFee);

        internalBalance[address(joe)] = internalBalance[address(joe)].add(
            amountMinusFee
        );
        user.rewardDebt[rewardToken] = user
            .amount
            .mul(accRewardPerShare[rewardToken])
            .div(PRECISION);

        if (user.amount > 0) {
            uint256 pending = previousAmount
                .mul(accRewardPerShare[rewardToken])
                .div(PRECISION)
                .sub(previousDebt);
            safeTokenTransfer(rewardToken, msg.sender, pending);
        }

        joe.safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(msg.sender, amountMinusFee);
    }

    /**
     * @notice get user info
     * @param _user The address of the user
     * @param _rewardToken The address of the reward token
     * @return uint256 the user's amount
     * @return uint256 the user's reward debt of the reward token chosen
     */
    function getUserInfo(address _user, address _rewardToken)
        external
        view
        returns (uint256, uint256)
    {
        UserInfo storage user = userInfo[_user];
        return (user.amount, user.rewardDebt[_rewardToken]);
    }

    /**
     * @notice Set the reward token
     * @param _rewardToken The address of the reward token
     */
    function setRewardToken(address _rewardToken) external onlyOwner {
        require(
            _rewardToken != address(0),
            "StableJoeStaking: reward token can't be address 0"
        );
        updatePool(_rewardToken);
        updatePool(rewardToken);
        rewardToken = _rewardToken;
    }

    /**
     * @notice Set the deposit fee percent
     * @param _depositFeePercent The new deposit fee percent
     */
    function setdepositFeePercent(uint256 _depositFeePercent)
        external
        onlyOwner
    {
        require(
            _depositFeePercent < PRECISION / 2,
            "StableJoeStaking: deposit fee can't be greater than 50%"
        );
        depositFeePercent = _depositFeePercent;
    }

    /**
     * @notice View function to see pending reward token on frontend
     * @param _user The address of the user
     * @return `_user`'s pending reward token
     */
    function pendingTokens(address _user, address _token)
        external
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[_user];
        uint256 totalJoe = internalBalance[address(joe)];
        uint256 _accRewardTokenPerShare = accRewardPerShare[_token];

        uint256 rewardBalance = IERC20Upgradeable(_token)
            .balanceOf(address(this))
            .sub(internalBalance[_token]);
        if (rewardBalance != lastRewardBalance[_token] && totalJoe != 0) {
            uint256 accruedRewards = rewardBalance.sub(
                lastRewardBalance[_token]
            );
            _accRewardTokenPerShare = _accRewardTokenPerShare.add(
                accruedRewards.mul(PRECISION).div(totalJoe)
            );
        }
        return
            user.amount.mul(_accRewardTokenPerShare).div(PRECISION).sub(
                user.rewardDebt[_token]
            );
    }

    /**
     * @notice Withdraw JOE from sJOE and harvest the rewards
     * @param _amount The amount of JOE to withdraw
     */
    function withdraw(uint256 _amount) external {
        UserInfo storage user = userInfo[msg.sender];
        require(
            user.amount >= _amount,
            "StableJoeStaking: withdraw amount exceeds balance"
        );

        updatePool(rewardToken);
        uint256 pending = user
            .amount
            .mul(accRewardPerShare[rewardToken])
            .div(PRECISION)
            .sub(user.rewardDebt[rewardToken]);

        user.amount = user.amount.sub(_amount);
        internalBalance[address(joe)] = internalBalance[address(joe)].sub(
            _amount
        );
        user.rewardDebt[rewardToken] = user
            .amount
            .mul(accRewardPerShare[rewardToken])
            .div(PRECISION);

        safeTokenTransfer(rewardToken, msg.sender, pending);
        joe.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @notice Withdraw without caring about rewards. EMERGENCY ONLY
     */
    function emergencyWithdraw() external {
        UserInfo storage user = userInfo[msg.sender];

        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt[rewardToken] = 0;

        joe.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _amount);
    }

    /**
     * @notice Update reward variables to be up-to-date
     * @param _token The address of the reward token
     * @dev Needs to be called before any deposit or withdrawal
     */
    function updatePool(address _token) public {
        uint256 rewardBalance = IERC20Upgradeable(_token)
            .balanceOf(address(this))
            .sub(internalBalance[_token]);
        uint256 totalJoe = internalBalance[address(joe)];

        // Did sJoe receive any token
        if (rewardBalance == lastRewardBalance[_token] || totalJoe == 0) {
            return;
        }

        uint256 accruedRewards = rewardBalance.sub(lastRewardBalance[_token]);

        accRewardPerShare[_token] = accRewardPerShare[_token].add(
            accruedRewards.mul(PRECISION).div(totalJoe)
        );
        lastRewardBalance[_token] = rewardBalance;
    }

    /**
     * @notice Claim reward
     * @param _token The address of the token
     * @param _user The userInfo
     */
    function _claimReward(address _token, UserInfo storage _user) internal {
        updatePool(_token);

        if (_user.amount > 0) {
            uint256 pending = _user
                .amount
                .mul(accRewardPerShare[_token])
                .div(PRECISION)
                .sub(_user.rewardDebt[_token]);
            _user.rewardDebt[_token] = _user
                .amount
                .mul(accRewardPerShare[_token])
                .div(PRECISION);
            safeTokenTransfer(_token, msg.sender, pending);
        }
    }

    /**
     * @notice Safe token transfer function, just in case if rounding error
     * causes pool to not have enough reward tokens
     * @param _token The address of then token to transfer
     * @param _to The address that will receive `_amount` `rewardToken`
     * @param _amount The amount to send to `_to`
     */
    function safeTokenTransfer(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        IERC20Upgradeable token = IERC20Upgradeable(_token);
        uint256 rewardBalance = token.balanceOf(address(this)).sub(
            internalBalance[_token]
        );
        if (_amount > rewardBalance) {
            lastRewardBalance[_token] = lastRewardBalance[_token].sub(
                rewardBalance
            );
            token.safeTransfer(_to, rewardBalance);
        } else {
            lastRewardBalance[_token] = lastRewardBalance[_token].sub(_amount);
            token.safeTransfer(_to, _amount);
        }
    }
}
