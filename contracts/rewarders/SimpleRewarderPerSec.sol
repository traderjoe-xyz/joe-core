// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../boringcrypto/BoringOwnable.sol";
import "../libraries/SafeERC20.sol";

interface IRewarder {
    using SafeERC20 for IERC20;

    function onJoeReward(address user, uint256 newLpAmount) external;

    function pendingTokens(address user) external view returns (uint256 pending);

    function rewardToken() external view returns (IERC20);
}

interface IMasterChefJoe {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this poolInfo. SUSHI to distribute per block.
        uint256 lastRewardTimestamp; // Last block timestamp that SUSHI distribution occurs.
        uint256 accJoePerShare; // Accumulated SUSHI per share, times 1e12. See below.
    }

    function poolInfo(uint256 pid) external view returns (PoolInfo memory);

    function totalAllocPoint() external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;
}

/**
 * This is a sample contract to be used in the MasterChefJoe contract for partners to reward
 * stakers with their native token alongside JOE.
 *
 * It assumes no minting rights, so requires a set amount of YOUR_TOKEN to be transferred to this contract prior.
 * E.g. say you've allocated 100,000 XYZ to the JOE-XYZ farm over 30 days. Then you would need to transfer
 * 100,000 XYZ and set the block reward accordingly so it's fully distributed after 30 days.
 *
 */
contract SimpleRewarderPerSec is IRewarder, BoringOwnable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable override rewardToken;
    IERC20 public immutable lpToken;
    bool public immutable isNative;
    IMasterChefJoe public immutable MCJ;

    /// @notice Info of each MCJ user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of YOUR_TOKEN entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    /// @notice Info of each MCJ poolInfo.
    /// `accTokenPerShare` Amount of YOUR_TOKEN each LP token is worth.
    /// `lastRewardTimestamp` The last timestamp YOUR_TOKEN was rewarded to the poolInfo.
    struct PoolInfo {
        uint256 accTokenPerShare;
        uint256 lastRewardTimestamp;
    }

    /// @notice Info of the poolInfo.
    PoolInfo public poolInfo;
    /// @notice Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    uint256 public tokenPerSec;
    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    event OnReward(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    modifier onlyMCJ() {
        require(msg.sender == address(MCJ), "onlyMCJ: only MasterChefJoe can call this function");
        _;
    }

    constructor(
        IERC20 _rewardToken,
        IERC20 _lpToken,
        uint256 _tokenPerSec,
        IMasterChefJoe _MCJ,
        bool _isNative
    ) public {
        require(Address.isContract(address(_rewardToken)), "constructor: reward token must be a valid contract");
        require(Address.isContract(address(_lpToken)), "constructor: LP token must be a valid contract");
        require(Address.isContract(address(_MCJ)), "constructor: MasterChefJoe must be a valid contract");

        rewardToken = _rewardToken;
        lpToken = _lpToken;
        tokenPerSec = _tokenPerSec;
        MCJ = _MCJ;
        isNative = _isNative;
        poolInfo = PoolInfo({lastRewardTimestamp: block.timestamp, accTokenPerShare: 0});
    }

    /// @notice Update reward variables of the given poolInfo.
    /// @return pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory pool) {
        pool = poolInfo;

        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = lpToken.balanceOf(address(MCJ));

            if (lpSupply > 0) {
                uint256 timeElapsed = block.timestamp.sub(pool.lastRewardTimestamp);
                uint256 tokenReward = timeElapsed.mul(tokenPerSec);
                pool.accTokenPerShare = pool.accTokenPerShare.add((tokenReward.mul(ACC_TOKEN_PRECISION) / lpSupply));
            }

            pool.lastRewardTimestamp = block.timestamp;
            poolInfo = pool;
        }
    }

    /// @notice Sets the distribution reward rate. This will also update the poolInfo.
    /// @param _tokenPerSec The number of tokens to distribute per second
    function setRewardRate(uint256 _tokenPerSec) external onlyOwner {
        updatePool();

        uint256 oldRate = tokenPerSec;
        tokenPerSec = _tokenPerSec;

        emit RewardRateUpdated(oldRate, _tokenPerSec);
    }

    /// @notice Function called by MasterChefJoe whenever staker claims JOE harvest. Allows staker to also receive a 2nd reward token.
    /// @param _user Address of user
    /// @param _lpAmount Number of LP tokens the user has
    function onJoeReward(address _user, uint256 _lpAmount) external override onlyMCJ nonReentrant {
        updatePool();
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 pending;
        if (user.amount > 0) {
            pending = (user.amount.mul(pool.accTokenPerShare) / ACC_TOKEN_PRECISION).sub(user.rewardDebt).add(
                user.unpaidRewards
            );

            if (isNative) {
                uint256 balance = address(this).balance;
                if (pending > balance) {
                    (bool success, ) = _user.call.value(balance)("");
                    require(success, "Transfer failed");
                    user.unpaidRewards = pending - balance;
                } else {
                    (bool success, ) = _user.call.value(pending)("");
                    require(success, "Transfer failed");
                    user.unpaidRewards = 0;
                }
            } else {
                uint256 balance = rewardToken.balanceOf(address(this));
                if (pending > balance) {
                    rewardToken.safeTransfer(_user, balance);
                    user.unpaidRewards = pending - balance;
                } else {
                    rewardToken.safeTransfer(_user, pending);
                    user.unpaidRewards = 0;
                }
            }
        }

        user.amount = _lpAmount;
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare) / ACC_TOKEN_PRECISION;
        emit OnReward(_user, pending - user.unpaidRewards);
    }

    /// @notice View function to see pending tokens
    /// @param _user Address of user.
    /// @return pending reward for a given user.
    function pendingTokens(address _user) external view override returns (uint256 pending) {
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];

        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = lpToken.balanceOf(address(MCJ));

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 timeElapsed = block.timestamp.sub(pool.lastRewardTimestamp);
            uint256 tokenReward = timeElapsed.mul(tokenPerSec);
            accTokenPerShare = accTokenPerShare.add(tokenReward.mul(ACC_TOKEN_PRECISION).div(lpSupply));
        }

        pending = (user.amount.mul(accTokenPerShare) / ACC_TOKEN_PRECISION).sub(user.rewardDebt).add(
            user.unpaidRewards
        );
    }

    /// @notice In case rewarder is stopped before emissions finished, this function allows
    /// withdrawal of remaining tokens.
    function emergencyWithdraw() public onlyOwner {
        if (isNative) {
            (bool success, ) = msg.sender.call.value(address(this).balance)("");
            require(success, "Transfer failed");
        } else {
            rewardToken.safeTransfer(address(msg.sender), rewardToken.balanceOf(address(this)));
        }
    }

    /// @notice View function to see balance of reward token.
    function balance() external view returns (uint256) {
        if (isNative) {
            return address(this).balance;
        } else {
            return rewardToken.balanceOf(address(this));
        }
    }

    /// @notice payable function needed to receive AVAX
    receive() external payable {}
}
