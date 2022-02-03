// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../boringcrypto/BoringOwnable.sol";
import "../libraries/SafeERC20.sol";
import "../traderjoe/JoePair.sol";

interface IERC20Metadata {
    function decimals() external returns (uint256);
}

interface IRewarder {
    using SafeERC20 for IERC20;

    function onJoeReward(address user, uint256 newLpAmount) external;

    function pendingTokens(address user)
        external
        view
        returns (uint256 pending);

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
 *
 * Issue with previous version is that this can return 0 or be very inacurate with some tokens:
 *      uint256 timeElapsed = block.timestamp.sub(pool.lastRewardTimestamp);
 *      uint256 tokenReward = timeElapsed.mul(tokenPerSec);
 *      accTokenPerShare = accTokenPerShare.add(
 *          tokenReward.mul(accTokenPrecision).div(lpSupply)
 *      );
 *  The goal with those changes is to prevent this, without any overflow too.
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

    uint256 private accTokenPrecision;
    // @dev decimals of pair
    uint256 private pairDecimals;
    // @dev decimals of reward token
    uint256 private rewardDecimals;

    event OnReward(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    modifier onlyMCJ() {
        require(
            msg.sender == address(MCJ),
            "onlyMCJ: only MasterChefJoe can call this function"
        );
        _;
    }

    constructor(
        IERC20 _rewardToken,
        IERC20 _lpToken,
        uint256 _tokenPerSec,
        IMasterChefJoe _MCJ,
        bool _isNative
    ) public {
        require(
            Address.isContract(address(_rewardToken)),
            "constructor: reward token must be a valid contract"
        );
        require(
            Address.isContract(address(_lpToken)),
            "constructor: LP token must be a valid contract"
        );
        require(
            Address.isContract(address(_MCJ)),
            "constructor: MasterChefJoe must be a valid contract"
        );

        rewardToken = _rewardToken;
        lpToken = _lpToken;
        tokenPerSec = _tokenPerSec;
        MCJ = _MCJ;
        isNative = _isNative;
        poolInfo = PoolInfo({
            lastRewardTimestamp: block.timestamp,
            accTokenPerShare: 0
        });

        JoePair pair = JoePair(address(_lpToken));
        IERC20Metadata token0 = IERC20Metadata(pair.token0());
        IERC20Metadata token1 = IERC20Metadata(pair.token1());
        pairDecimals = (token0.decimals() + token1.decimals()) / 2;
        rewardDecimals = IERC20Metadata(address(_rewardToken)).decimals();

        // Edge case n1:
        // `lpSupply` is in 18 decimals and is very tiny, 1 WEI
        // `tokenPerSec` is in 18 decimals, and we expect it to not be greater than 1e(12 + 18)
        // `updatePool` is updated every at least every 31 years, i.e. 1e9 seconds
        // decimals of result:
        // result = 1e9 * 1e30 * 1e12 / 1
        //        = 1e51
        //
        // Edge case n2:
        // `lpSupply` is in 18 decimals and is very tiny, and is very big, i.e. 1e(18 + 12)
        // `tokenPerSec` is equal to 1e(18 + 6)
        // `updatePool` is updated every 1s, i.e. 1 seconds
        // decimals of result:
        // result = 1 * 1e24 * 1e12 / 1e30
        //        = 1e6
        //
        // Edge case n3:
        // `lpSupply` is in 18 decimals and is very tiny, 1 WEI
        // `rewardToken` is in 18 decimals, and is very big, 1e(18+6)-1
        // `updatePool` is updated every at least every 31 years, i.e. 1e9 seconds
        // decimals of result:
        // result = 1e9 * 1e24 * 1e(19 + 18 - 24) / 1
        //        = 1e9 * 1e24 * 1e(13) / 1
        //        = 1e46
        //
        // Edge case n4:
        // `lpSupply` is in 18 decimals and is very big, 1e(12+18)
        // `tokenPerSec` is very small, i.e 1 WEI
        // `updatePool` is updated every 1s, i.e. 1 seconds
        // decimals of result:
        // result = 1 * 1 * 1e(19 + 18 - 1) / 1e30
        //        = 1 * 1 * 1e36 / 1e30
        //        = 1e6
        uint256 tokenPerSecDecimals;
        for (; _tokenPerSec != 0; _tokenPerSec /= 10) tokenPerSecDecimals++;

        // We want at least 6 decimals and as we expect lpSupply to to not be greater than 10**(12 + pairDecimals)
        if (tokenPerSecDecimals >= pairDecimals + 6) {
            accTokenPrecision = 1e12;
        } else {
            accTokenPrecision = 10**(19 + pairDecimals - tokenPerSecDecimals);
        }
    }

    /// @notice Update reward variables of the given poolInfo.
    /// @return pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory pool) {
        pool = poolInfo;

        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = lpToken.balanceOf(address(MCJ));

            if (lpSupply > 0) {
                uint256 timeElapsed = block.timestamp.sub(
                    pool.lastRewardTimestamp
                );
                uint256 tokenReward = timeElapsed.mul(tokenPerSec);
                pool.accTokenPerShare = pool.accTokenPerShare.add(
                    (tokenReward.mul(accTokenPrecision) / lpSupply)
                );
            }

            pool.lastRewardTimestamp = block.timestamp;
            poolInfo = pool;
        }
    }

    /// @notice Sets the distribution reward rate. This will also update the poolInfo.
    /// @param _tokenPerSec The number of tokens to distribute per second
    function setRewardRate(uint256 _tokenPerSec) external onlyOwner {
        updatePool();

        PoolInfo memory pool = poolInfo;
        uint256 oldAccTokenPrecision = accTokenPrecision;

        uint256 oldRate = tokenPerSec;
        tokenPerSec = _tokenPerSec;

        uint256 tokenPerSecDecimals;
        uint256 newTokenPerSec = _tokenPerSec;
        for (; newTokenPerSec != 0; newTokenPerSec /= 10) tokenPerSecDecimals++;

        // We want at least 6 decimals and as we expect lpSupply to to not be greater than 10**(12 + pairDecimals)
        if (tokenPerSecDecimals >= pairDecimals + 6) {
            accTokenPrecision = 1e12;
        } else {
            accTokenPrecision = 10**(19 + pairDecimals - tokenPerSecDecimals);
        }

        // We need to update `accTokenPerShare` to have the right precision
        if (oldAccTokenPrecision != accTokenPrecision) {
            if (oldAccTokenPrecision > accTokenPrecision)
                poolInfo.accTokenPerShare.div(
                    oldAccTokenPrecision / accTokenPrecision
                );
            else
                poolInfo.accTokenPerShare.mul(
                    oldAccTokenPrecision / accTokenPrecision
                );
        }

        emit RewardRateUpdated(oldRate, _tokenPerSec);
    }

    /// @notice Function called by MasterChefJoe whenever staker claims JOE harvest. Allows staker to also receive a 2nd reward token.
    /// @param _user Address of user
    /// @param _lpAmount Number of LP tokens the user has
    function onJoeReward(address _user, uint256 _lpAmount)
        external
        override
        onlyMCJ
        nonReentrant
    {
        updatePool();
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 pending;
        if (user.amount > 0) {
            pending = (user.amount.mul(pool.accTokenPerShare) /
                accTokenPrecision).sub(user.rewardDebt).add(user.unpaidRewards);

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
        user.rewardDebt =
            user.amount.mul(pool.accTokenPerShare) /
            accTokenPrecision;
        emit OnReward(_user, pending - user.unpaidRewards);
    }

    /// @notice View function to see pending tokens
    /// @param _user Address of user.
    /// @return pending reward for a given user.
    function pendingTokens(address _user)
        external
        view
        override
        returns (uint256 pending)
    {
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];

        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = lpToken.balanceOf(address(MCJ));

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 timeElapsed = block.timestamp.sub(pool.lastRewardTimestamp);
            uint256 tokenReward = timeElapsed.mul(tokenPerSec);
            accTokenPerShare = accTokenPerShare.add(
                tokenReward.mul(accTokenPrecision).div(lpSupply)
            );
        }

        pending = (user.amount.mul(accTokenPerShare) / accTokenPrecision)
            .sub(user.rewardDebt)
            .add(user.unpaidRewards);
    }

    /// @notice In case rewarder is stopped before emissions finished, this function allows
    /// withdrawal of remaining tokens.
    function emergencyWithdraw() public onlyOwner {
        if (isNative) {
            (bool success, ) = msg.sender.call.value(address(this).balance)("");
            require(success, "Transfer failed");
        } else {
            rewardToken.safeTransfer(
                address(msg.sender),
                rewardToken.balanceOf(address(this))
            );
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
