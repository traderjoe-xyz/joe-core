// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IMasterChefJoe.sol";
import "./interfaces/IRewarder.sol";
import "./libraries/BoringJoeERC20.sol";

/// @notice The (older) MasterChefJoeV2 contract gives out a constant number of JOE
/// tokens per block.  It is the only address with minting rights for JOE.  The idea
/// for this BoostedMasterChefJoe (BMCJ) contract is therefore to be the owner of a
/// dummy token that is deposited into the MasterChefJoeV2 (MCJV2) contract.  The
/// allocation point for this pool on MCJV2 is the total allocation point for all
/// pools on BMCJ.
///
/// This MasterChef also skews how many rewards users receive, it does this by
/// modifying the algorithm that calculates how many tokens are rewarded to
/// depositors. Whereas MasterChef calculates rewards based on emission rate and
/// total liquidity, this version uses adjusted parameters to this calculation.
///
/// A users `boostedAmount` (liquidity multiplier) is calculated by the actual supplied
/// liquidity multiplied by a boost factor. The boost factor is calculated by the
/// amount of veJOE held by the user over the total veJOE amount held by all pool
/// participants. Total liquidity is the sum of all boosted liquidity.
contract BoostedMasterChefJoe is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using BoringJoeERC20 for IERC20;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /// @notice Info of each BMCJ user
    /// `amount` LP token amount the user has provided
    /// `rewardDebt` The amount of JOE entitled to the user
    /// `veJoeBalance` the users balance of veJOE token. This needs
    /// to be stored so we have a prior value when updating the `PoolInfo`
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 veJoeBalance;
    }

    /// @notice Info of each BMCJ pool
    /// `allocPoint` The amount of allocation points assigned to the pool
    /// Also known as the amount of JOE to distribute per block
    struct PoolInfo {
        IERC20 lpToken;
        uint256 accJoePerShare;
        uint256 lastRewardTimestamp;
        uint256 allocPoint;
        IRewarder rewarder;
        // The sum of all veJoe held by users participating in this farm
        // This value is updated when
        // - A user enter/leaves a farm
        // - A user claims veJOE
        // - A user unstakes JOE
        uint256 totalVeJoe;
        // The total boosted `amount` on the farm
        // This is the sum of all users boosted amounts in the farm. Updated when
        // totalVeJoe is updated
        // This is used instead of the usual `lpToken.balanceOf(address(this))`
        uint256 totalBoostedAmount;
        // Even though it seems redundant to keep track of two variables here
        // the `totalBoostedAmount` means we don't need to iterate over all
        // depositors to calculate the pending reward.
    }

    /// @notice Address of MCJV2 contract
    IMasterChefJoe public MASTER_CHEF_V2;
    /// @notice Address of JOE contract
    IERC20 public JOE;
    /// @notice Address of veJOE contract
    IERC20 public VEJOE;
    /// @notice The index of BMCJ master pool in MCJV2
    uint256 public MASTER_PID;

    /// @notice Info of each BMCJ pool
    PoolInfo[] public poolInfo;
    /// @dev Set of all LP tokens that have been added as pools
    EnumerableSetUpgradeable.AddressSet private lpTokens;

    /// @notice Info of each user that stakes LP tokens
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools
    uint256 public totalAllocPoint;
    uint256 private ACC_TOKEN_PRECISION;

    /// @dev A maximum scaling factor applied to boosted amounts
    uint256 public maxBoostFactor;
    /// @dev Amount of claimable Joe the user has, this is required as we
    /// need to update rewardDebt after a token operation but we don't
    /// want to send a reward at this point. This amount gets added onto
    /// the pending amount when a user claims
    mapping(uint256 => mapping(address => uint256)) public claimableJoe;

    event Add(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IRewarder indexed rewarder);
    event Set(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(uint256 indexed pid, uint256 lastRewardTimestamp, uint256 lpSupply, uint256 accJoePerShare);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Init(uint256 amount);

    /// @param _MASTER_CHEF_V2 The MCJV2 contract address
    /// @param _joe The JOE token contract address
    /// @param _veJoe The veJOE token contract address
    /// @param _MASTER_PID The pool ID of the dummy token on the base MCJV2 contract
    function initialize(
        IMasterChefJoe _MASTER_CHEF_V2,
        IERC20 _joe,
        IERC20 _veJoe,
        uint256 _MASTER_PID
    ) public initializer {
        __Ownable_init();
        MASTER_CHEF_V2 = _MASTER_CHEF_V2;
        JOE = _joe;
        VEJOE = _veJoe;
        MASTER_PID = _MASTER_PID;

        ACC_TOKEN_PRECISION = 1e18;
        maxBoostFactor = 1500;
    }

    /// @notice Deposits a dummy token to `MASTER_CHEF_V2` MCJV2. This is required because MCJV2
    /// holds the minting rights for JOE.  Any balance of transaction sender in `_dummyToken` is transferred.
    /// The allocation point for the pool on MCJV2 is the total allocation point for all pools that receive
    /// double incentives.
    /// @param _dummyToken The address of the ERC-20 token to deposit into MCJV2.
    function init(IERC20 _dummyToken) external onlyOwner {
        require(
            _dummyToken.balanceOf(address(MASTER_CHEF_V2)) == 0,
            "BoostedMasterChefJoe: Already has a balance of dummy token"
        );
        uint256 balance = _dummyToken.balanceOf(msg.sender);
        require(balance != 0, "BoostedMasterChefJoe: Balance must exceed 0");
        _dummyToken.safeTransferFrom(msg.sender, address(this), balance);
        _dummyToken.approve(address(MASTER_CHEF_V2), balance);
        MASTER_CHEF_V2.deposit(MASTER_PID, balance);
        emit Init(balance);
    }

    /// @notice Returns the number of BMCJ pools.
    /// @return pools The amount of pools in this farm
    function poolLength() external view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// @param _allocPoint AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    /// @param _rewarder Address of the rewarder delegate.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        IRewarder _rewarder
    ) external onlyOwner {
        require(!lpTokens.contains(address(_lpToken)), "BoostedMasterChefJoe: LP already added");
        require(poolInfo.length <= 50, "BoostedMasterChefJoe: Too many pools");
        // Sanity check to ensure _lpToken is an ERC20 token
        _lpToken.balanceOf(address(this));
        // Sanity check if we add a rewarder
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(address(0), 0);
        }

        uint256 lastRewardTimestamp = block.timestamp;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accJoePerShare: 0,
                rewarder: _rewarder,
                totalVeJoe: 0,
                totalBoostedAmount: 0
            })
        );
        lpTokens.add(address(_lpToken));
        emit Add(poolInfo.length.sub(1), _allocPoint, _lpToken, _rewarder);
    }

    /// @notice Update the given pool's JOE allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _allocPoint New AP of the pool
    /// @param _rewarder Address of the rewarder delegate
    /// @param _overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        IRewarder _rewarder,
        bool _overwrite
    ) external onlyOwner {
        PoolInfo memory pool = poolInfo[_pid];
        totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);
        pool.allocPoint = _allocPoint;
        if (_overwrite) {
            if (address(_rewarder) != address(0)) {
                _rewarder.onJoeReward(address(0), 0);
            }
            pool.rewarder = _rewarder;
        }
        poolInfo[_pid] = pool;
        emit Set(_pid, _allocPoint, _overwrite ? _rewarder : pool.rewarder, _overwrite);
    }

    /// @notice View function to see pending JOE on frontend
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _user Address of user
    /// @return pendingJoe JOE reward for a given user.
    /// @return bonusTokenAddress The address of the bonus reward.
    /// @return bonusTokenSymbol The symbol of the bonus token.
    /// @return pendingBonusToken The amount of bonus rewards pending.
    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 pendingJoe,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        )
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accJoePerShare = pool.accJoePerShare;

        if (block.timestamp > pool.lastRewardTimestamp && pool.totalBoostedAmount != 0) {
            uint256 secondsElapsed = block.timestamp.sub(pool.lastRewardTimestamp);
            uint256 joeReward = secondsElapsed.mul(joePerSec()).mul(pool.allocPoint).div(totalAllocPoint);
            accJoePerShare = accJoePerShare.add(joeReward.mul(ACC_TOKEN_PRECISION).div(pool.totalBoostedAmount));
        }

        uint256 userLiquidity = getBoostedLiquidity(_pid, _user);
        pendingJoe = userLiquidity.mul(accJoePerShare).div(ACC_TOKEN_PRECISION).sub(user.rewardDebt).add(
            claimableJoe[_pid][_user]
        );

        // If it's a double reward farm, we return info about the bonus token
        if (address(pool.rewarder) != address(0)) {
            bonusTokenAddress = address(pool.rewarder.rewardToken());
            bonusTokenSymbol = IERC20(pool.rewarder.rewardToken()).safeSymbol();
            pendingBonusToken = pool.rewarder.pendingTokens(_user);
        }
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param _pids Pool IDs of all to be updated. Make sure to update all active pools
    function massUpdatePools(uint256[] calldata _pids) external {
        uint256 len = _pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(_pids[i]);
        }
    }

    /// @notice Calculates and returns the `amount` of JOE per second
    /// @return amount The amount of JOE emitted per second
    function joePerSec() public view returns (uint256 amount) {
        uint256 total = 1000;
        uint256 lpPercent = total.sub(MASTER_CHEF_V2.devPercent()).sub(MASTER_CHEF_V2.treasuryPercent()).sub(
            MASTER_CHEF_V2.investorPercent()
        );
        uint256 lpShare = MASTER_CHEF_V2.joePerSec().mul(lpPercent).div(total);
        amount = lpShare.mul(MASTER_CHEF_V2.poolInfo(MASTER_PID).allocPoint).div(MASTER_CHEF_V2.totalAllocPoint());
    }

    /// @notice Update reward variables of the given pool
    /// @param _pid The index of the pool. See `poolInfo`
    function updatePool(uint256 _pid) public {
        PoolInfo memory pool = poolInfo[_pid];
        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            if (lpSupply != 0) {
                uint256 secondsElapsed = block.timestamp.sub(pool.lastRewardTimestamp);
                uint256 joeReward = secondsElapsed.mul(joePerSec()).mul(pool.allocPoint).div(totalAllocPoint);
                pool.accJoePerShare = pool.accJoePerShare.add(
                    joeReward.mul(ACC_TOKEN_PRECISION).div(pool.totalBoostedAmount)
                );
            }
            pool.lastRewardTimestamp = block.timestamp;
            poolInfo[_pid] = pool;
            emit UpdatePool(_pid, pool.lastRewardTimestamp, lpSupply, pool.accJoePerShare);
        }
    }

    /// @notice Deposit LP tokens to BMCJ for JOE allocation
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _amount LP token amount to deposit
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        harvestFromMasterChef();
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        // Pay a user any pending rewards
        if (user.amount != 0) {
            // Harvest JOE
            uint256 boostedLiquidity = getBoostedLiquidity(_pid, msg.sender);

            uint256 pending = boostedLiquidity
                .mul(pool.accJoePerShare)
                .div(ACC_TOKEN_PRECISION)
                .sub(user.rewardDebt)
                .add(claimableJoe[_pid][msg.sender]);
            claimableJoe[_pid][msg.sender] = 0;
            JOE.safeTransfer(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }

        uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
        pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 receivedAmount = pool.lpToken.balanceOf(address(this)).sub(balanceBefore);

        // Effects

        // Update the `pool.totalVeJoe`
        uint256 veJoeBalance = VEJOE.balanceOf(msg.sender);
        if (veJoeBalance != 0) {
            pool.totalVeJoe = pool.totalVeJoe.add(veJoeBalance).sub(user.veJoeBalance);
        }
        user.veJoeBalance = veJoeBalance;

        // Update the `pool.totalBoostedAmount`
        uint256 boostedLiquidityBefore = getBoostedLiquidity(_pid, msg.sender);
        user.amount = user.amount.add(receivedAmount);
        uint256 boostedLiquidityAfter = getBoostedLiquidity(_pid, msg.sender);

        pool.totalBoostedAmount = pool.totalBoostedAmount.add(boostedLiquidityAfter).sub(boostedLiquidityBefore);

        // Update users reward debt
        user.rewardDebt = boostedLiquidityAfter.mul(pool.accJoePerShare).div(ACC_TOKEN_PRECISION);

        // Interactions
        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, user.amount);
        }
        emit Deposit(msg.sender, _pid, receivedAmount);
    }

    /// @notice Withdraw LP tokens from BMCJ
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _amount LP token amount to withdraw
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        harvestFromMasterChef();
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.amount != 0) {
            // Harvest JOE
            uint256 boostedLiquidity = getBoostedLiquidity(_pid, msg.sender);

            uint256 pending = boostedLiquidity
                .mul(pool.accJoePerShare)
                .div(ACC_TOKEN_PRECISION)
                .sub(user.rewardDebt)
                .add(claimableJoe[_pid][msg.sender]);
            claimableJoe[_pid][msg.sender] = 0;
            JOE.safeTransfer(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }

        // Effects
        uint256 boostedLiquidityBefore = getBoostedLiquidity(_pid, msg.sender);
        user.amount = user.amount.sub(_amount);
        uint256 boostedLiquidityAfter = getBoostedLiquidity(_pid, msg.sender);
        // Update the `pool.totalBoostedAmount` and `totalVeJoe` if needed
        if (user.amount == 0) {
            pool.totalVeJoe = pool.totalVeJoe.sub(user.veJoeBalance);
        }

        pool.totalBoostedAmount = pool.totalBoostedAmount.add(boostedLiquidityAfter).sub(boostedLiquidityBefore);
        user.rewardDebt = boostedLiquidityAfter.mul(pool.accJoePerShare).div(ACC_TOKEN_PRECISION);

        // Interactions
        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, user.amount);
        }

        pool.lpToken.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    /// @notice Updates a pool and user boost factors after
    /// a veJoe token operation. This function needs to be called
    /// by the veJoe contract after every event.
    /// @param _user The users address we are updating
    /// @param _newUserBalance The new balance of the users veJoe
    function updateBoost(address _user, uint256 _newUserBalance) external {
        require(msg.sender == address(VEJOE), "BoostedMasterChefJoe: Caller not veJOE");

        uint256 length = poolInfo.length;

        for (uint256 pid = 0; pid < length; ++pid) {
            UserInfo storage user = userInfo[pid][_user];

            // Skip if user doesn't have any deposit in the pool
            if (user.amount == 0) {
                continue;
            }

            PoolInfo storage pool = poolInfo[pid];
            updatePool(pid);
            // Calculate pending
            uint256 oldBoostedLiquidity = getBoostedLiquidity(pid, _user);
            uint256 pending = oldBoostedLiquidity.mul(pool.accJoePerShare).div(ACC_TOKEN_PRECISION).sub(
                user.rewardDebt
            );

            // Increase claimableJoe
            claimableJoe[pid][_user] = claimableJoe[pid][_user].add(pending);

            // Update users veJoeBalance
            uint256 _oldBalance = user.veJoeBalance;
            user.veJoeBalance = _newUserBalance;

            // Update the pool total veJoe
            pool.totalVeJoe = pool.totalVeJoe.add(_newUserBalance).sub(_oldBalance);

            uint256 newBoostedLiquidity = getBoostedLiquidity(pid, _user);

            // Update the pools total boosted
            pool.totalBoostedAmount = pool.totalBoostedAmount.add(newBoostedLiquidity).sub(oldBoostedLiquidity);

            // Update reward debt, take into account new boost
            user.rewardDebt = newBoostedLiquidity.mul(pool.accJoePerShare).div(ACC_TOKEN_PRECISION);
        }
    }

    /// @notice Returns a users "boosted" liquidity
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _user The address of the depositor
    /// @return boostedLiquidity The users liquidity multiplied by their boost
    function getBoostedLiquidity(uint256 _pid, address _user) public view returns (uint256 boostedLiquidity) {
        UserInfo memory user = userInfo[_pid][_user];
        boostedLiquidity = user.amount.mul(getUserBoost(_pid, _user)).div(1000);
    }

    /// @notice Returns a users boosted emission share
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _user The address of the depositor
    /// @dev `userBoost` is scaled by 1e3
    /// @return userBoost A multiplier for a users liquidity
    function getUserBoost(uint256 _pid, address _user) public view returns (uint256 userBoost) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        userBoost = 1000;
        if (user.veJoeBalance != 0 && pool.totalVeJoe != 0) {
            userBoost = userBoost.add(user.veJoeBalance.mul(maxBoostFactor).div(pool.totalVeJoe));
        }
    }

    /// @notice Harvests JOE from `MASTER_CHEF_V2` MCJV2 and pool `MASTER_PID` to this BMCJ contract
    function harvestFromMasterChef() public {
        MASTER_CHEF_V2.deposit(MASTER_PID, 0);
    }

    /// @notice Withdraw without caring about rewards (EMERGENCY ONLY)
    /// @param _pid The index of the pool. See `poolInfo`
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(msg.sender, 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero
        pool.lpToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }
}
