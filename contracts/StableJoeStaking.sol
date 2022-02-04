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
 * Every time `updateReward(token)` is called, We distribute the balance of that tokens as rewards to users that are
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
        mapping(IERC20Upgradeable => uint256) rewardDebt;
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

    /// @notice Internal balance of $JOE, this gets updated on user deposits / withdrawals
    /// @dev this allows to reward users with $JOE.
    uint256 internalJoeBalance;
    /// @notice The array of token that people can claim to get reward
    IERC20Upgradeable[] public rewardTokens;
    mapping(IERC20Upgradeable => bool) public isRewardToken;
    /// @notice Last reward balance of `token`
    mapping(IERC20Upgradeable => uint256) public lastRewardBalance;

    address public feeCollector;

    /// @notice The deposit fee, scaled to `PRECISION`
    uint256 public depositFeePercent;

    /// @notice Accumulated `token` rewards per share, scaled to `PRECISION`. See above
    mapping(IERC20Upgradeable => uint256) public accRewardPerShare;
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
        IERC20Upgradeable _rewardToken,
        IERC20Upgradeable _joe,
        address _feeCollector,
        uint256 _depositFeePercent
    ) external initializer {
        __Ownable_init();
        require(_feeCollector != address(0), "StableJoeStaking: fee collector can't be address 0");
        require(_depositFeePercent < 5e17, "StableJoeStaking: max deposit fee can't be greater than 50%");

        joe = _joe;
        depositFeePercent = _depositFeePercent;
        feeCollector = _feeCollector;

        isRewardToken[_rewardToken] = true;
        rewardTokens.push(_rewardToken);
        PRECISION = 1e24;
    }

    /**
     * @notice Deposit JOE for reward token allocation
     * @param _amount The amount of JOE to deposit
     */
    function deposit(uint256 _amount) external {
        UserInfo storage user = userInfo[msg.sender];

        uint256 fee = (_amount * depositFeePercent) / 1e18;
        uint256 amountMinusFee = _amount.sub(fee);

        uint256 previousAmount = user.amount;
        uint256 newAmount = user.amount.add(amountMinusFee);
        user.amount = newAmount;

        uint256 len = rewardTokens.length;
        uint256 pending;
        for (uint256 i; i < len; i++) {
            IERC20Upgradeable token = rewardTokens[i];
            updateReward(token);

            if (previousAmount > 0) {
                pending = previousAmount.mul(accRewardPerShare[token]).div(PRECISION).sub(user.rewardDebt[token]);
                if (pending != 0) safeTokenTransfer(token, msg.sender, pending);
            }
            user.rewardDebt[token] = newAmount.mul(accRewardPerShare[token]).div(PRECISION);
        }

        internalJoeBalance = internalJoeBalance.add(amountMinusFee);
        joe.safeTransferFrom(msg.sender, feeCollector, fee);
        joe.safeTransferFrom(msg.sender, address(this), amountMinusFee);
        emit Deposit(msg.sender, amountMinusFee);
    }

    /**
     * @notice get user info
     * @param _user The address of the user
     * @param _rewardToken The address of the reward token
     * @return uint256 the user's amount
     * @return uint256 the user's reward debt of the reward token chosen
     */
    function getUserInfo(address _user, IERC20Upgradeable _rewardToken) external view returns (uint256, uint256) {
        UserInfo storage user = userInfo[_user];
        return (user.amount, user.rewardDebt[_rewardToken]);
    }

    /**
     * @notice get the number of reward tokens
     * @return The length of the array
     */
    function rewardTokensLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    /**
     * @notice Set the reward token
     * @param _rewardToken The address of the reward token
     */
    function addRewardToken(IERC20Upgradeable _rewardToken) external onlyOwner {
        require(
            !isRewardToken[_rewardToken] && address(_rewardToken) != address(0),
            "StableJoeStaking: token can't be added"
        );
        rewardTokens.push(_rewardToken);
        isRewardToken[_rewardToken] = true;
        updateReward(_rewardToken);
    }

    /**
     * @notice Remove a reward token
     * @param _rewardToken The address of the reward token
     */
    function removeRewardToken(IERC20Upgradeable _rewardToken) external onlyOwner {
        require(isRewardToken[_rewardToken], "StableJoeStaking: token can't be removed");
        updateReward(_rewardToken);
        isRewardToken[_rewardToken] = false;
        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            if (rewardTokens[i] == _rewardToken) {
                rewardTokens[i] = rewardTokens[len - 1];
                rewardTokens.pop();
                break;
            }
        }
    }

    /**
     * @notice Set the deposit fee percent
     * @param _depositFeePercent The new deposit fee percent
     */
    function setdepositFeePercent(uint256 _depositFeePercent) external onlyOwner {
        require(_depositFeePercent < 5e17, "StableJoeStaking: deposit fee can't be greater than 50%");
        depositFeePercent = _depositFeePercent;
    }

    /**
     * @notice View function to see pending reward token on frontend
     * @param _user The address of the user
     * @return `_user`'s pending reward token
     */
    function pendingReward(address _user, IERC20Upgradeable _token) external view returns (uint256) {
        require(isRewardToken[_token], "StableJoeStaking: wrong reward token");
        UserInfo storage user = userInfo[_user];
        uint256 totalJoe = internalJoeBalance;
        uint256 _accRewardTokenPerShare = accRewardPerShare[_token];

        uint256 rewardBalance;
        if (_token == joe) rewardBalance = _token.balanceOf(address(this)).sub(internalJoeBalance);
        else rewardBalance = _token.balanceOf(address(this));
        if (rewardBalance != lastRewardBalance[_token] && totalJoe != 0) {
            uint256 accruedReward = rewardBalance.sub(lastRewardBalance[_token]);
            _accRewardTokenPerShare = _accRewardTokenPerShare.add(accruedReward.mul(PRECISION).div(totalJoe));
        }
        return user.amount.mul(_accRewardTokenPerShare).div(PRECISION).sub(user.rewardDebt[_token]);
    }

    /**
     * @notice Withdraw JOE from sJOE and harvest the rewards
     * @param _amount The amount of JOE to withdraw
     */
    function withdraw(uint256 _amount) external {
        UserInfo storage user = userInfo[msg.sender];
        uint256 previousAmount = user.amount;
        require(previousAmount >= _amount, "StableJoeStaking: withdraw amount exceeds balance");
        uint256 newAmount = user.amount.sub(_amount);
        user.amount = newAmount;

        uint256 len = rewardTokens.length;
        uint256 pending;
        if (previousAmount > 0) {
            for (uint256 i; i < len; i++) {
                IERC20Upgradeable token = rewardTokens[i];
                updateReward(token);

                pending = previousAmount.mul(accRewardPerShare[token]).div(PRECISION).sub(user.rewardDebt[token]);
                if (pending != 0) safeTokenTransfer(token, msg.sender, pending);
                user.rewardDebt[token] = newAmount.mul(accRewardPerShare[token]).div(PRECISION);
            }
        }

        internalJoeBalance = internalJoeBalance.sub(_amount);
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
        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            IERC20Upgradeable token = rewardTokens[i];
            user.rewardDebt[token] = 0;
        }
        joe.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _amount);
    }

    /**
     * @notice Update reward variables to be up-to-date
     * @param _token The address of the reward token
     * @dev Needs to be called before any deposit or withdrawal
     */
    function updateReward(IERC20Upgradeable _token) public {
        require(isRewardToken[_token], "StableJoeStaking: wrong reward token");
        uint256 rewardBalance;
        if (_token == joe) rewardBalance = _token.balanceOf(address(this)).sub(internalJoeBalance);
        else rewardBalance = _token.balanceOf(address(this));
        uint256 totalJoe = internalJoeBalance;

        // Did sJoe receive any token
        if (rewardBalance == lastRewardBalance[_token] || totalJoe == 0) {
            return;
        }

        uint256 accruedReward = rewardBalance.sub(lastRewardBalance[_token]);

        accRewardPerShare[_token] = accRewardPerShare[_token].add(accruedReward.mul(PRECISION).div(totalJoe));
        lastRewardBalance[_token] = rewardBalance;
    }

    /**
     * @notice Safe token transfer function, just in case if rounding error
     * causes pool to not have enough reward tokens
     * @param _token The address of then token to transfer
     * @param _to The address that will receive `_amount` `rewardToken`
     * @param _amount The amount to send to `_to`
     */
    function safeTokenTransfer(
        IERC20Upgradeable _token,
        address _to,
        uint256 _amount
    ) internal {
        uint256 rewardBalance;
        if (_token == joe) rewardBalance = _token.balanceOf(address(this)).sub(internalJoeBalance);
        else rewardBalance = _token.balanceOf(address(this));

        if (_amount > rewardBalance) {
            lastRewardBalance[_token] = lastRewardBalance[_token].sub(rewardBalance);
            _token.safeTransfer(_to, rewardBalance);
        } else {
            lastRewardBalance[_token] = lastRewardBalance[_token].sub(_amount);
            _token.safeTransfer(_to, _amount);
        }
    }
}
