/// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title Stable Joe Staking
 * @author traderjoexyz
 * @notice StableJoeStaking is a contract that allows to deposit moJoe and receives stable coin sent by JoeMakerV4's daily
 * harvests. Users deposit moJoe and receive a share of what has been sent by JoeMakerV4 based on their participation
 * of the total deposited moJoe.
 */
contract StableJoeStaking is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Info of each user.
    struct UserInfo {
        uint256 amount; /// @notice How many LP rewardTokens the user has provided.
        uint256 rewardDebt; /// @notice The sum of rewards already paid to this account. See explanation below.
        /**
         * @notice We do some fancy math here. Basically, any point in time, the amount of JOEs
         * entitled to a user but is pending to be distributed is:
         *
         *   pending reward = (user.amount * accTokenPerShare) - user.rewardDebt
         *
         * Whenever a user deposits or withdraws moJoe. Here's what happens:
         *   1. accTokenPerShare (and `lastTokenBalance`) gets updated.
         *   2. User receives the pending reward sent to his/her address.
         *   3. User's `amount` gets updated.
         *   4. User's `rewardDebt` gets updated.
         */
    }

    /// @notice Info.
    IERC20Upgradeable moJoe; /// @notice Address of moJoe contract.
    uint256 lastTokenBalance; /// @notice Last balance of reward token.
    uint256 accTokenPerShare; /// @notice Accumulated Tokens per share, times 1e12. See above.

    /// @notice The reward token.
    IERC20Upgradeable public rewardToken;

    /// @notice Info of each user that stakes moJoe.
    mapping(address => UserInfo) public userInfo;

    /// @notice Emitted when a user deposits its moJOE
    event Deposit(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws its moJOE
    event Withdraw(address indexed user, uint256 amount);

    /// @notice Emitted when a user emergency withdraws its moJOE
    event EmergencyWithdraw(address indexed user, uint256 amount);

    /**
     * @notice Initialize a new StableJoeStaking contract.
     * @dev This contract needs to receive an ERC20 `_rewardToken` in order to distribute them
     * (with JoeMakerV4 in our case)
     * @param _rewardToken The address of the ERC-20 reward token
     * @param _moJoe The address of the ERC-20 moJOE token, traderjoe's staking token.
     */
    function initialize(IERC20Upgradeable _rewardToken, IERC20Upgradeable _moJoe) public initializer {
        __Ownable_init();

        rewardToken = _rewardToken;
        moJoe = _moJoe;
    }

    /**
     * @notice View function to see pending reward token on frontend.
     * @param _user The address of the user
     * @return `_user`'s pending reward token
     */
    function pendingToken(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 lpSupply = moJoe.balanceOf(address(this));
        uint256 _accTokenPerShare = accTokenPerShare;

        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        if (rewardTokenBalance != lastTokenBalance && lpSupply != 0) {
            uint256 rewardTokenAdded = rewardTokenBalance.sub(lastTokenBalance);
            _accTokenPerShare = _accTokenPerShare.add(rewardTokenAdded.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(_accTokenPerShare).div(1e12).sub(user.rewardDebt);
    }

    /**
     * @notice Update reward variables to be up-to-date.
     * @dev Needs to be called before any deposit or withdrawal.
     */
    function updatePool() public {
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        if (rewardTokenBalance == lastTokenBalance) {
            return;
        }

        uint256 lpSupply = moJoe.balanceOf(address(this));
        if (lpSupply == 0) {
            lastTokenBalance = rewardTokenBalance;
            return;
        }

        uint256 rewardTokenAdded = rewardTokenBalance.sub(lastTokenBalance);
        accTokenPerShare = accTokenPerShare.add(rewardTokenAdded.mul(1e12).div(lpSupply));
        lastTokenBalance = rewardTokenBalance;
    }

    /**
     * @notice Deposit moJoe to sJoe for reward token allocation.
     * @param _amount The amount of moJOE to deposit
     */
    function deposit(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];

        updatePool();
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
            safeTokenTransfer(msg.sender, pending);
        }
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(accTokenPerShare).div(1e12);

        moJoe.safeTransferFrom(address(msg.sender), address(this), _amount);
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice Withdraw moJoe from sJoe and harvest the rewards.
     * @param _amount The amount of moJOE to withdraw
     */
    function withdraw(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool();
        uint256 pending = user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);

        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(accTokenPerShare).div(1e12);

        safeTokenTransfer(msg.sender, pending);
        moJoe.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @notice Withdraw without caring about rewards. EMERGENCY ONLY.
     */
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];

        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        moJoe.safeTransfer(address(msg.sender), _amount);
        emit EmergencyWithdraw(msg.sender, _amount);
    }

    /**
     * @notice Safe Token transfer function, just in case if rounding error
     * causes pool to not have enough reward tokens.
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
