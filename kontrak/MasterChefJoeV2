// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./JoeToken.sol";
import "./libraries/BoringERC20.sol";
import "hardhat/console.sol";

interface IRewarder {
    using SafeERC20 for IERC20;

    function onJoeReward(address user, uint256 newLpAmount) external;

    function pendingTokens(address user) external view returns (uint256 pending);

    function rewardToken() external view returns (address);
}

// MasterChefJoe is a boss. He says "go f your blocks lego boy, I'm gonna use timestamp instead".
// And to top it off, it takes no risks. Because the biggest risk is operator error.
// So we make it virtually impossible for the operator of this contract to cause a bug with people's harvests.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once JOE is sufficiently
// distributed and the community can show to govern itself.
//
// With thanks to the Lydia Finance team.
//
// Godspeed and may the 10x be with you.
contract MasterChefJoeV2 is Ownable {
    using SafeMath for uint256;
    using BoringERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of JOEs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accJoePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accJoePerShare` (and `lastRewardTimestamp`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. JOEs to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that JOEs distribution occurs.
        uint256 accJoePerShare; // Accumulated JOEs per share, times 1e12. See below.
        IRewarder rewarder;
    }

    // The JOE TOKEN!
    JoeToken public joe;
    // Dev address.
    address public devAddr;
    // Treasury address.
    address public treasuryAddr;
    // Investor address
    address public investorAddr;
    // JOE tokens created per second.
    uint256 public joePerSec;
    // Percentage of pool rewards that goto the devs.
    uint256 public devPercent;
    // Percentage of pool rewards that goes to the treasury.
    uint256 public treasuryPercent;
    // Percentage of pool rewards that goes to the investor.
    uint256 public investorPercent;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Set of all LP tokens that have been added as pools
    EnumerableSet.AddressSet private lpTokens;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The timestamp when JOE mining starts.
    uint256 public startTimestamp;

    event Add(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IRewarder indexed rewarder);
    event Set(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(uint256 indexed pid, uint256 lastRewardTimestamp, uint256 lpSupply, uint256 accJoePerShare);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetDevAddress(address indexed oldAddress, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 _joePerSec);

    constructor(
        JoeToken _joe,
        address _devAddr,
        address _treasuryAddr,
        address _investorAddr,
        uint256 _joePerSec,
        uint256 _startTimestamp,
        uint256 _devPercent,
        uint256 _treasuryPercent,
        uint256 _investorPercent
    ) public {
        require(0 <= _devPercent && _devPercent <= 1000, "constructor: invalid dev percent value");
        require(0 <= _treasuryPercent && _treasuryPercent <= 1000, "constructor: invalid treasury percent value");
        require(0 <= _investorPercent && _investorPercent <= 1000, "constructor: invalid investor percent value");
        require(_devPercent + _treasuryPercent + _investorPercent <= 1000, "constructor: total percent over max");
        joe = _joe;
        devAddr = _devAddr;
        treasuryAddr = _treasuryAddr;
        investorAddr = _investorAddr;
        joePerSec = _joePerSec;
        startTimestamp = _startTimestamp;
        devPercent = _devPercent;
        treasuryPercent = _treasuryPercent;
        investorPercent = _investorPercent;
        totalAllocPoint = 0;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        IRewarder _rewarder
    ) public onlyOwner {
        require(Address.isContract(address(_lpToken)), "add: LP token must be a valid contract");
        require(
            Address.isContract(address(_rewarder)) || address(_rewarder) == address(0),
            "add: rewarder must be contract or zero"
        );
        require(!lpTokens.contains(address(_lpToken)), "add: LP already added");
        massUpdatePools();
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accJoePerShare: 0,
                rewarder: _rewarder
            })
        );
        lpTokens.add(address(_lpToken));
        emit Add(poolInfo.length.sub(1), _allocPoint, _lpToken, _rewarder);
    }

    // Update the given pool's JOE allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        IRewarder _rewarder,
        bool overwrite
    ) public onlyOwner {
        require(
            Address.isContract(address(_rewarder)) || address(_rewarder) == address(0),
            "set: rewarder must be contract or zero"
        );
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        if (overwrite) {
            poolInfo[_pid].rewarder = _rewarder;
        }
        emit Set(_pid, _allocPoint, overwrite ? _rewarder : poolInfo[_pid].rewarder, overwrite);
    }

    // View function to see pending JOEs on frontend.
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
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accJoePerShare = pool.accJoePerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 multiplier = block.timestamp.sub(pool.lastRewardTimestamp);
            uint256 lpPercent = 1000 - devPercent - treasuryPercent - investorPercent;
            uint256 joeReward = multiplier.mul(joePerSec).mul(pool.allocPoint).div(totalAllocPoint).mul(lpPercent).div(
                1000
            );
            accJoePerShare = accJoePerShare.add(joeReward.mul(1e12).div(lpSupply));
        }
        pendingJoe = user.amount.mul(accJoePerShare).div(1e12).sub(user.rewardDebt);

        // If it's a double reward farm, we return info about the bonus token
        if (address(pool.rewarder) != address(0)) {
            (bonusTokenAddress, bonusTokenSymbol) = rewarderBonusTokenInfo(_pid);
            pendingBonusToken = pool.rewarder.pendingTokens(_user);
        }
    }

    // Get bonus token info from the rewarder contract for a given pool, if it is a double reward farm
    function rewarderBonusTokenInfo(uint256 _pid)
        public
        view
        returns (address bonusTokenAddress, string memory bonusTokenSymbol)
    {
        PoolInfo storage pool = poolInfo[_pid];
        if (address(pool.rewarder) != address(0)) {
            bonusTokenAddress = address(pool.rewarder.rewardToken());
            bonusTokenSymbol = IERC20(pool.rewarder.rewardToken()).safeSymbol();
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 multiplier = block.timestamp.sub(pool.lastRewardTimestamp);
        uint256 joeReward = multiplier.mul(joePerSec).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 lpPercent = 1000 - devPercent - treasuryPercent - investorPercent;
        joe.mint(devAddr, joeReward.mul(devPercent).div(1000));
        joe.mint(treasuryAddr, joeReward.mul(treasuryPercent).div(1000));
        joe.mint(investorAddr, joeReward.mul(investorPercent).div(1000));
        joe.mint(address(this), joeReward.mul(lpPercent).div(1000));
        pool.accJoePerShare = pool.accJoePerShare.add(joeReward.mul(1e12).div(lpSupply).mul(lpPercent).div(1000));
        pool.lastRewardTimestamp = block.timestamp;
        emit UpdatePool(_pid, pool.lastRewardTimestamp, lpSupply, pool.accJoePerShare);
    }

    // Deposit LP tokens to MasterChef for JOE allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            // Harvest JOE
            uint256 pending = user.amount.mul(pool.accJoePerShare).div(1e12).sub(user.rewardDebt);
            safeJoeTransfer(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accJoePerShare).div(1e12);

        IRewarder rewarder = poolInfo[_pid].rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onJoeReward(msg.sender, user.amount);
        }

        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

        // Harvest JOE
        uint256 pending = user.amount.mul(pool.accJoePerShare).div(1e12).sub(user.rewardDebt);
        safeJoeTransfer(msg.sender, pending);
        emit Harvest(msg.sender, _pid, pending);

        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accJoePerShare).div(1e12);

        IRewarder rewarder = poolInfo[_pid].rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onJoeReward(msg.sender, user.amount);
        }

        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe joe transfer function, just in case if rounding error causes pool to not have enough JOEs.
    function safeJoeTransfer(address _to, uint256 _amount) internal {
        uint256 joeBal = joe.balanceOf(address(this));
        if (_amount > joeBal) {
            joe.transfer(_to, joeBal);
        } else {
            joe.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devAddr) public {
        require(msg.sender == devAddr, "dev: wut?");
        devAddr = _devAddr;
        emit SetDevAddress(msg.sender, _devAddr);
    }

    function setDevPercent(uint256 _newDevPercent) public onlyOwner {
        require(0 <= _newDevPercent && _newDevPercent <= 1000, "setDevPercent: invalid percent value");
        require(treasuryPercent + _newDevPercent + investorPercent <= 1000, "setDevPercent: total percent over max");
        devPercent = _newDevPercent;
    }

    // Update treasury address by the previous treasury.
    function setTreasuryAddr(address _treasuryAddr) public {
        require(msg.sender == treasuryAddr, "setTreasuryAddr: wut?");
        treasuryAddr = _treasuryAddr;
    }

    function setTreasuryPercent(uint256 _newTreasuryPercent) public onlyOwner {
        require(0 <= _newTreasuryPercent && _newTreasuryPercent <= 1000, "setTreasuryPercent: invalid percent value");
        require(
            devPercent + _newTreasuryPercent + investorPercent <= 1000,
            "setTreasuryPercent: total percent over max"
        );
        treasuryPercent = _newTreasuryPercent;
    }

    // Update the investor address by the previous investor.
    function setInvestorAddr(address _investorAddr) public {
        require(msg.sender == investorAddr, "setInvestorAddr: wut?");
        investorAddr = _investorAddr;
    }

    function setInvestorPercent(uint256 _newInvestorPercent) public onlyOwner {
        require(0 <= _newInvestorPercent && _newInvestorPercent <= 1000, "setInvestorPercent: invalid percent value");
        require(
            devPercent + _newInvestorPercent + treasuryPercent <= 1000,
            "setInvestorPercent: total percent over max"
        );
        investorPercent = _newInvestorPercent;
    }

    // Pancake has to add hidden dummy pools inorder to alter the emission,
    // here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _joePerSec) public onlyOwner {
        massUpdatePools();
        joePerSec = _joePerSec;
        emit UpdateEmissionRate(msg.sender, _joePerSec);
    }
}
