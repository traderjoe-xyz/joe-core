// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// StableJoeStaking is a contract that allows to deposit moJoe and receives stable coin sent by JoeMakerV4's daily
// harvests. Users deposit moJoe and receive a share of what has been sent by JoeMakerV4 based on their participation
// of the total deposited moJoe.

contract StableJoeStaking is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP rewardTokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of JOEs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * accTokenPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws moJoe. Here's what happens:
        //   1. accTokenPerShare (and `lastTokenBalance`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info.
    IERC20Upgradeable moJoe; // Address of moJoe contract.
    uint256 lastTokenBalance; // Last balance of reward token.
    uint256 accTokenPerShare; // Accumulated Tokens per share, times 1e12. See above.

    // The reward token.
    IERC20Upgradeable public rewardToken;

    // Info of each user that stakes moJoe.
    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    function initialize(IERC20Upgradeable _rewardToken, IERC20Upgradeable _moJoe) public initializer {
        __Ownable_init();

        rewardToken = _rewardToken;
        moJoe = _moJoe;
    }

    // View function to see pending reward token on frontend.
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

    // Update reward variables to be up-to-date.
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

    // Deposit moJoe to sJoe for reward token allocation.
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

    // Withdraw moJoe from sJoe and harvest the rewards.
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

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];

        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        moJoe.safeTransfer(address(msg.sender), _amount);
        emit EmergencyWithdraw(msg.sender, _amount);
    }

    // Safe Token transfer function, just in case if rounding error causes pool to not have enough reward tokens.
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
