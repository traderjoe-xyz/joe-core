// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IMasterChefJoe.sol";
import "./interfaces/IRewarder.sol";
import "./libraries/BoringJoeERC20.sol";
import "./traderjoe/libraries/Math.sol";

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
    using BoringJoeERC20 for IERC20;
    using SafeMathUpgradeable for uint256;

    /// @notice Info of each BMCJ user
    /// `amount` LP token amount the user has provided
    /// `rewardDebt` The amount of JOE entitled to the user
    /// `factor` the users factor, use _getUserFactor
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 factor;
    }

    /// @notice Info of each BMCJ pool
    /// `allocPoint` The amount of allocation points assigned to the pool
    /// Also known as the amount of JOE to distribute per block
    struct PoolInfo {
        // Address are stored in 160 bits, so we store allocPoint in 96 bits to
        // optimize storage (160 + 96 = 256)
        IERC20 lpToken;
        uint96 allocPoint;
        uint256 accJoePerShare;
        uint256 accJoePerFactorPerShare;
        // Address are stored in 160 bits, so we store lastRewardTimestamp in 64 bits and
        // veJoeShareBp in 32 bits to optimize storage (160 + 64 + 32 = 256)
        uint64 lastRewardTimestamp;
        IRewarder rewarder;
        // Share of the reward to distribute to veJoe holders
        uint32 veJoeShareBp;
        // The sum of all veJoe held by users participating in this farm
        // This value is updated when
        // - A user enter/leaves a farm
        // - A user claims veJOE
        // - A user unstakes JOE
        uint256 totalFactor;
        // The total LP supply of the farm
        // This is the sum of all users boosted amounts in the farm. Updated when
        // someone deposits or withdraws.
        // This is used instead of the usual `lpToken.balanceOf(address(this))` for security reasons
        uint256 totalLpSupply;
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
    /// @dev Maps an address to a bool to assert that a token isn't added twice
    mapping(IERC20 => bool) private checkPoolDuplicate;

    /// @notice Info of each user that stakes LP tokens
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools
    uint256 public totalAllocPoint;
    uint256 private ACC_TOKEN_PRECISION;

    /// @dev Amount of claimable Joe the user has, this is required as we
    /// need to update rewardDebt after a token operation but we don't
    /// want to send a reward at this point. This amount gets added onto
    /// the pending amount when a user claims
    mapping(uint256 => mapping(address => uint256)) public claimableJoe;

    event Add(
        uint256 indexed pid,
        uint256 allocPoint,
        uint256 veJoeShareBp,
        IERC20 indexed lpToken,
        IRewarder indexed rewarder
    );
    event Set(
        uint256 indexed pid,
        uint256 allocPoint,
        uint256 veJoeShareBp,
        IRewarder indexed rewarder,
        bool overwrite
    );
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(
        uint256 indexed pid,
        uint256 lastRewardTimestamp,
        uint256 lpSupply,
        uint256 accJoePerShare,
        uint256 accJoePerFactorPerShare
    );
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
        uint256 balance = _dummyToken.balanceOf(_msgSender());
        require(balance != 0, "BoostedMasterChefJoe: Balance must exceed 0");
        _dummyToken.safeTransferFrom(_msgSender(), address(this), balance);
        _dummyToken.approve(address(MASTER_CHEF_V2), balance);
        MASTER_CHEF_V2.deposit(MASTER_PID, balance);
        emit Init(balance);
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// @param _allocPoint AP of the new pool.
    /// @param _veJoeShareBp Share of rewards allocated in proportion to user's liquidity
    /// and veJoe balance
    /// @param _lpToken Address of the LP ERC-20 token.
    /// @param _rewarder Address of the rewarder delegate.
    function add(
        uint96 _allocPoint,
        uint32 _veJoeShareBp,
        IERC20 _lpToken,
        IRewarder _rewarder
    ) external onlyOwner {
        require(!checkPoolDuplicate[_lpToken], "BoostedMasterChefJoe: LP already added");
        require(_veJoeShareBp <= 10_000, "BoostedMasterChefJoe: veJoeShareBp needs to be lower than 10000");
        require(poolInfo.length <= 50, "BoostedMasterChefJoe: Too many pools");
        checkPoolDuplicate[_lpToken] = true;
        // Sanity check to ensure _lpToken is an ERC20 token
        _lpToken.balanceOf(address(this));
        // Sanity check if we add a rewarder
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(address(0), 0);
        }

        massUpdatePools();

        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                accJoePerShare: 0,
                accJoePerFactorPerShare: 0,
                lastRewardTimestamp: uint64(block.timestamp),
                rewarder: _rewarder,
                veJoeShareBp: _veJoeShareBp,
                totalFactor: 0,
                totalLpSupply: 0
            })
        );
        emit Add(poolInfo.length - 1, _allocPoint, _veJoeShareBp, _lpToken, _rewarder);
    }

    /// @notice Update the given pool's JOE allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _allocPoint New AP of the pool
    /// @param _veJoeShareBp Share of rewards allocated in proportion to user's liquidity
    /// and veJoe balance
    /// @param _rewarder Address of the rewarder delegate
    /// @param _overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored
    function set(
        uint256 _pid,
        uint96 _allocPoint,
        uint32 _veJoeShareBp,
        IRewarder _rewarder,
        bool _overwrite
    ) external onlyOwner {
        require(_veJoeShareBp <= 10_000, "BoostedMasterChefJoe: veJoeShareBp needs to be lower than 10000");
        massUpdatePools();

        PoolInfo storage pool = poolInfo[_pid];
        totalAllocPoint = totalAllocPoint.add(_allocPoint).sub(pool.allocPoint);
        pool.allocPoint = _allocPoint;
        pool.veJoeShareBp = _veJoeShareBp;
        if (_overwrite) {
            if (address(_rewarder) != address(0)) {
                // Sanity check
                _rewarder.onJoeReward(address(0), 0);
            }
            pool.rewarder = _rewarder;
        }

        emit Set(_pid, _allocPoint, _veJoeShareBp, _overwrite ? _rewarder : pool.rewarder, _overwrite);
    }

    /// @notice Deposit LP tokens to BMCJ for JOE allocation
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _amount LP token amount to deposit
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        harvestFromMasterChef();
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];

        // Pay a user any pending rewards
        if (user.amount != 0) {
            _harvestJoe(user, pool, _pid);
        }

        uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
        pool.lpToken.safeTransferFrom(_msgSender(), address(this), _amount);
        uint256 receivedAmount = pool.lpToken.balanceOf(address(this)).sub(balanceBefore);

        _updateUserAndPool(user, pool, receivedAmount, true);

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(_msgSender(), user.amount);
        }
        emit Deposit(_msgSender(), _pid, receivedAmount);
    }

    /// @notice Withdraw LP tokens from BMCJ
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _amount LP token amount to withdraw
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        harvestFromMasterChef();
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        require(user.amount >= _amount, "BoostedMasterChefJoe: withdraw not good");

        if (user.amount != 0) {
            _harvestJoe(user, pool, _pid);
        }

        _updateUserAndPool(user, pool, _amount, false);

        pool.lpToken.safeTransfer(_msgSender(), _amount);

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(_msgSender(), user.amount);
        }
        emit Withdraw(_msgSender(), _pid, _amount);
    }

    /// @notice Updates factor after after a veJoe token operation.
    /// This function needs to be called by the veJoe contract after
    /// every mint / burn.
    /// @param _user The users address we are updating
    /// @param _newVeJoeBalance The new balance of the users veJoe
    function updateFactor(address _user, uint256 _newVeJoeBalance) external {
        require(_msgSender() == address(VEJOE), "BoostedMasterChefJoe: Caller not veJOE");
        uint256 len = poolInfo.length;
        uint256 _ACC_TOKEN_PRECISION = ACC_TOKEN_PRECISION;

        for (uint256 pid; pid < len; ++pid) {
            UserInfo storage user = userInfo[pid][_user];

            // Skip if user doesn't have any deposit in the pool
            uint256 amount = user.amount;
            if (amount == 0) {
                continue;
            }

            PoolInfo storage pool = poolInfo[pid];

            updatePool(pid);
            uint256 oldFactor = user.factor;
            (uint256 accJoePerShare, uint256 accJoePerFactorPerShare) = (
                pool.accJoePerShare,
                pool.accJoePerFactorPerShare
            );
            uint256 pending = amount
                .mul(accJoePerShare)
                .add(oldFactor.mul(accJoePerFactorPerShare))
                .div(_ACC_TOKEN_PRECISION)
                .sub(user.rewardDebt);

            // Increase claimableJoe
            claimableJoe[pid][_user] = claimableJoe[pid][_user].add(pending);

            // Update users veJoeBalance
            uint256 newFactor = _getUserFactor(amount, _newVeJoeBalance);
            user.factor = newFactor;
            pool.totalFactor = pool.totalFactor.add(newFactor).sub(oldFactor);

            user.rewardDebt = amount.mul(accJoePerShare).add(newFactor.mul(accJoePerFactorPerShare)).div(
                _ACC_TOKEN_PRECISION
            );

            // Update the pool total veJoe
        }
    }

    /// @notice Withdraw without caring about rewards (EMERGENCY ONLY)
    /// @param _pid The index of the pool. See `poolInfo`
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];

        pool.totalFactor = pool.totalFactor.sub(user.factor);
        pool.totalLpSupply = pool.totalLpSupply.sub(user.amount);
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.factor = 0;

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(_msgSender(), 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero
        pool.lpToken.safeTransfer(_msgSender(), amount);
        emit EmergencyWithdraw(_msgSender(), _pid, amount);
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
        UserInfo memory user = userInfo[_pid][_user];
        uint256 accJoePerShare = pool.accJoePerShare;
        uint256 accJoePerFactorPerShare = pool.accJoePerFactorPerShare;

        if (block.timestamp > pool.lastRewardTimestamp && pool.totalLpSupply != 0 && pool.allocPoint != 0) {
            uint256 secondsElapsed = block.timestamp - pool.lastRewardTimestamp;
            uint256 joeReward = secondsElapsed.mul(joePerSec()).mul(pool.allocPoint).div(totalAllocPoint);
            accJoePerShare = accJoePerShare.add(
                joeReward.mul(ACC_TOKEN_PRECISION).mul(10_000 - pool.veJoeShareBp).div(pool.totalLpSupply.mul(10_000))
            );
            if (pool.veJoeShareBp != 0 && pool.totalFactor != 0) {
                accJoePerFactorPerShare = accJoePerFactorPerShare.add(
                    joeReward.mul(ACC_TOKEN_PRECISION).mul(pool.veJoeShareBp).div(pool.totalFactor.mul(10_000))
                );
            }
        }

        pendingJoe = (user.amount.mul(accJoePerShare))
            .add(user.factor.mul(accJoePerFactorPerShare))
            .div(ACC_TOKEN_PRECISION)
            .add(claimableJoe[_pid][_user])
            .sub(user.rewardDebt);

        // If it's a double reward farm, we return info about the bonus token
        if (address(pool.rewarder) != address(0)) {
            bonusTokenAddress = address(pool.rewarder.rewardToken());
            bonusTokenSymbol = IERC20(bonusTokenAddress).safeSymbol();
            pendingBonusToken = pool.rewarder.pendingTokens(_user);
        }
    }

    /// @notice Returns the number of BMCJ pools.
    /// @return pools The amount of pools in this farm
    function poolLength() external view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 len = poolInfo.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(i);
        }
    }

    /// @notice Update reward variables of the given pool
    /// @param _pid The index of the pool. See `poolInfo`
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lastRewardTimestamp = pool.lastRewardTimestamp;
        if (block.timestamp > lastRewardTimestamp) {
            uint256 lpSupply = pool.totalLpSupply;
            uint256 allocPoint = pool.allocPoint;
            // gas opt and prevent div by 0
            if (lpSupply != 0 && allocPoint != 0) {
                uint256 secondsElapsed = block.timestamp - lastRewardTimestamp;
                uint256 veJoeShareBp = pool.veJoeShareBp;
                uint256 totalFactor = pool.totalFactor;

                uint256 joeReward = secondsElapsed.mul(joePerSec()).mul(allocPoint).div(totalAllocPoint);
                pool.accJoePerShare = pool.accJoePerShare.add(
                    joeReward.mul(ACC_TOKEN_PRECISION).mul(10_000 - veJoeShareBp).div(lpSupply.mul(10_000))
                );
                // If veJoeShareBp is 0, then we don't need to update it
                if (veJoeShareBp != 0 && totalFactor != 0) {
                    pool.accJoePerFactorPerShare = pool.accJoePerFactorPerShare.add(
                        joeReward.mul(ACC_TOKEN_PRECISION).mul(veJoeShareBp).div(totalFactor.mul(10_000))
                    );
                }
            }
            pool.lastRewardTimestamp = uint64(block.timestamp);
            emit UpdatePool(
                _pid,
                pool.lastRewardTimestamp,
                lpSupply,
                pool.accJoePerShare,
                pool.accJoePerFactorPerShare
            );
        }
    }

    /// @notice Harvests JOE from `MASTER_CHEF_V2` MCJV2 and pool `MASTER_PID` to this BMCJ contract
    function harvestFromMasterChef() public {
        MASTER_CHEF_V2.deposit(MASTER_PID, 0);
    }

    /// @notice Return an user's factor
    /// @param amount The user's amount of liquidity
    /// @param veJoeBalance The user's veJoe balance
    /// @return uint256 The user's factor
    function _getUserFactor(uint256 amount, uint256 veJoeBalance) private pure returns (uint256) {
        return Math.sqrt(amount * veJoeBalance);
    }

    /// @notice Updates user and pool infos
    /// @param _user The user that needs to be updated
    /// @param _pool The pool that needs to be updated
    /// @param _amount The amount that was deposited or withdrawn
    /// @param _isDeposit If the action of the user is a deposit
    function _updateUserAndPool(
        UserInfo storage _user,
        PoolInfo storage _pool,
        uint256 _amount,
        bool _isDeposit
    ) private {
        uint256 oldAmount = _user.amount;
        uint256 newAmount = _isDeposit ? oldAmount.add(_amount) : oldAmount.sub(_amount);

        if (_amount != 0) {
            _user.amount = newAmount;
            _pool.totalLpSupply = _isDeposit ? _pool.totalLpSupply.add(_amount) : _pool.totalLpSupply.sub(_amount);
        }

        uint256 oldFactor = _user.factor;
        uint256 newFactor = _getUserFactor(newAmount, VEJOE.balanceOf(_msgSender()));

        if (oldFactor != newFactor) {
            _user.factor = newFactor;
            _pool.totalFactor = _pool.totalFactor.add(newFactor).sub(oldFactor);
        }

        _user.rewardDebt = newAmount.mul(_pool.accJoePerShare).add(newFactor.mul(_pool.accJoePerFactorPerShare)).div(
            ACC_TOKEN_PRECISION
        );
    }

    /// @notice Harvests user's pending JOE
    /// @dev WARNING this function doesn't update user's rewardDebt,
    /// it still needs to be updated in order for this contract to work properlly
    /// @param _user The user that will harvest its rewards
    /// @param _pool The pool where the user staked and want to harvest its JOE
    /// @param _pid The pid of that pool
    function _harvestJoe(
        UserInfo storage _user,
        PoolInfo storage _pool,
        uint256 _pid
    ) private {
        uint256 pending = (_user.amount.mul(_pool.accJoePerShare))
            .add(_user.factor.mul(_pool.accJoePerFactorPerShare))
            .div(ACC_TOKEN_PRECISION)
            .add(claimableJoe[_pid][_msgSender()])
            .sub(_user.rewardDebt);
        claimableJoe[_pid][_msgSender()] = 0;
        if (pending != 0) {
            JOE.safeTransfer(_msgSender(), pending);
            emit Harvest(_msgSender(), _pid, pending);
        }
    }
}
