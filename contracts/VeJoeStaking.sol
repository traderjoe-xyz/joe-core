// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./VeJoeToken.sol";

/// @title Vote Escrow Joe Staking
/// @author Trader Joe
/// @notice Stake JOE to earn veJOE, which you can use to earn higher farm yields and gain
/// voting power. Note that unstaking any amount of JOE will burn all of your existing veJOE.
contract VeJoeStaking is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Info for each user
    /// `balance`: Amount of JOE currently staked by user
    /// `rewardDebt`: The reward debt of the user
    struct UserInfo {
        uint256 balance;
        uint256 rewardDebt;
    }

    IERC20Upgradeable public joe;
    VeJoeToken public veJoe;

    /// @notice The maximum ratio of veJOE to staked JOE
    /// For example, if user has `n` JOE staked, they can own a maximum of `n * maxCap` veJOE.
    uint256 public maxCap;

    /// @notice The upper limit of `maxCap`
    uint256 public upperLimitMaxCap;

    /// @notice The accrued veJoe per share, scaled to `ACC_VEJOE_PER_SHARE_PRECISION`
    uint256 public accVeJoePerShare;

    /// @notice Precision of `accVeJoePerShare`
    uint256 public ACC_VEJOE_PER_SHARE_PRECISION;

    /// @notice The last time that the reward variables were updated
    uint256 public lastRewardTimestamp;

    /// @notice Rate of veJOE generated per sec per JOE staked, scaled to `GENERATION_RATE_PRECISION`
    uint256 public baseGenerationRate;

    /// @notice Precision of `baseGenerationRate`
    uint256 public GENERATION_RATE_PRECISION;

    mapping(address => UserInfo) public userInfos;

    event Claim(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event UpdateBaseGenerationRate(address indexed user, uint256 baseGenerationRate);
    event UpdateMaxCap(address indexed user, uint256 maxCap);
    event UpdateRewardVars(uint256 lastRewardTimestamp, uint256 accVeJoePerShare);
    event Withdraw(address indexed user, uint256 amount);

    /// @notice Initialize with needed parameters
    /// @param _joe Address of the JOE token contract
    /// @param _veJoe Address of the veJOE token contract
    /// @param _baseGenerationRate Rate of veJOE generated per sec per JOE staked
    /// @param _maxCap the maximum amount of veJOE received per JOE staked
    function initialize(
        IERC20Upgradeable _joe,
        VeJoeToken _veJoe,
        uint256 _baseGenerationRate,
        uint256 _maxCap
    ) public initializer {
        require(address(_joe) != address(0), "VeJoeStaking: unexpected zero address for _joe");
        require(address(_veJoe) != address(0), "VeJoeStaking: unexpected zero address for _veJoe");

        upperLimitMaxCap = 100000;
        require(
            _maxCap != 0 && _maxCap <= upperLimitMaxCap,
            "VeJoeStaking: expected new _maxCap to be non-zero and <= 100000"
        );

        __Ownable_init();

        maxCap = _maxCap;
        joe = _joe;
        veJoe = _veJoe;
        baseGenerationRate = _baseGenerationRate;
        lastRewardTimestamp = block.timestamp;
        ACC_VEJOE_PER_SHARE_PRECISION = 1e18;
        GENERATION_RATE_PRECISION = 1e18;
    }

    /// @notice Set maxCap
    /// @param _maxCap The new maxCap
    function setMaxCap(uint256 _maxCap) external onlyOwner {
        require(_maxCap > maxCap, "VeJoeStaking: expected new _maxCap to be greater than existing maxCap");
        require(
            _maxCap != 0 && _maxCap <= upperLimitMaxCap,
            "VeJoeStaking: expected new _maxCap to be non-zero and <= 100000"
        );
        maxCap = _maxCap;
        emit UpdateMaxCap(msg.sender, _maxCap);
    }

    /// @notice Set baseGenerationRate
    /// @param _baseGenerationRate The new baseGenerationRate
    function setBaseGenerationRate(uint256 _baseGenerationRate) external onlyOwner {
        updateRewardVars();
        baseGenerationRate = _baseGenerationRate;
        emit UpdateBaseGenerationRate(msg.sender, _baseGenerationRate);
    }

    /// @notice Deposits JOE to start staking for veJOE. Note that any pending veJOE
    /// will also be claimed in the process.
    /// @param _amount The amount of JOE to deposit
    function deposit(uint256 _amount) external {
        require(_amount > 0, "VeJoeStaking: expected deposit amount to be greater than zero");

        updateRewardVars();
        // Transfer to the user their pending veJOE before updating their UserInfo
        if (_getUserHasNonZeroBalance(msg.sender)) {
            _claim();
        }

        UserInfo storage userInfo = userInfos[msg.sender];

        userInfo.balance = userInfo.balance.add(_amount);
        userInfo.rewardDebt = accVeJoePerShare.mul(userInfo.balance).div(ACC_VEJOE_PER_SHARE_PRECISION);

        joe.safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _amount);
    }

    /// @notice Withdraw staked JOE. Note that unstaking any amount of JOE means you will
    /// lose all of your current veJOE.
    /// @param _amount The amount of JOE to unstake
    function withdraw(uint256 _amount) external {
        require(_amount > 0, "VeJoeStaking: expected withdraw amount to be greater than zero");

        UserInfo storage userInfo = userInfos[msg.sender];

        require(
            userInfo.balance >= _amount,
            "VeJoeStaking: cannot withdraw greater amount of JOE than currently staked"
        );
        updateRewardVars();

        // Note that we don't need to claim as the user's veJOE balance will be reset to 0
        userInfo.balance = userInfo.balance.sub(_amount);
        userInfo.rewardDebt = accVeJoePerShare.mul(userInfo.balance).div(ACC_VEJOE_PER_SHARE_PRECISION);

        // Burn the user's current veJOE balance
        veJoe.burnFrom(msg.sender, veJoe.balanceOf(msg.sender));

        // Send user their requested amount of staked JOE
        joe.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /// @notice Claim any pending veJOE
    function claim() external {
        require(_getUserHasNonZeroBalance(msg.sender), "VeJoeStaking: cannot claim veJOE when no JOE is staked");
        updateRewardVars();
        _claim();
    }

    /// @notice Get the pending amount of veJOE for a given user
    /// @param _user The user to lookup
    /// @return The number of pending veJOE tokens for `_user`
    function getPendingVeJoe(address _user) public view returns (uint256) {
        if (!_getUserHasNonZeroBalance(_user)) {
            return 0;
        }

        UserInfo memory user = userInfos[_user];

        // Calculate amount of pending veJOE
        uint256 _accVeJoePerShare = accVeJoePerShare;
        uint256 secondsElapsed = block.timestamp.sub(lastRewardTimestamp);
        if (secondsElapsed > 0) {
            _accVeJoePerShare = _accVeJoePerShare.add(
                secondsElapsed.mul(baseGenerationRate).mul(ACC_VEJOE_PER_SHARE_PRECISION).div(GENERATION_RATE_PRECISION)
            );
        }

        pendingVeJoe = _accVeJoePerShare.mul(user.balance).div(ACC_VEJOE_PER_SHARE_PRECISION).sub(user.rewardDebt);

        // Get the user's current veJOE balance and maximum veJOE they can hold
        uint256 userVeJoeBalance = veJoe.balanceOf(_user);
        uint256 userMaxVeJoeCap = user.balance.mul(maxCap);

        if (userVeJoeBalance >= userMaxVeJoeCap) {
            // User already holds maximum amount of veJOE so there is no pending veJOE
            return 0;
        } else if (userVeJoeBalance.add(pendingVeJoe) > userMaxVeJoeCap) {
            return userMaxVeJoeCap.sub(userVeJoeBalance);
        } else {
            return pendingVeJoe;
        }
    }

    /// @notice Update reward variables
    function updateRewardVars() public {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        if (joe.balanceOf(address(this)) == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 secondsElapsed = block.timestamp.sub(lastRewardTimestamp);
        accVeJoePerShare = accVeJoePerShare.add(
            secondsElapsed.mul(baseGenerationRate).mul(ACC_VEJOE_PER_SHARE_PRECISION).div(GENERATION_RATE_PRECISION)
        );
        lastRewardTimestamp = block.timestamp;

        emit UpdateRewardVars(lastRewardTimestamp, accVeJoePerShare);
    }

    /// @notice Checks to see if a given user currently has staked JOE
    /// @param _user The user address to check
    /// @return Whether `_user` currently has staked JOE
    function _getUserHasNonZeroBalance(address _user) private view returns (bool) {
        return userInfos[_user].balance > 0;
    }

    /// @dev Helper to claim any pending veJOE
    function _claim() private {
        uint256 veJoeToClaim = getPendingVeJoe(msg.sender);

        UserInfo storage userInfo = userInfos[msg.sender];

        userInfo.rewardDebt = accVeJoePerShare.mul(userInfo.balance).div(ACC_VEJOE_PER_SHARE_PRECISION);

        if (veJoeToClaim > 0) {
            veJoe.mint(msg.sender, veJoeToClaim);
            emit Claim(msg.sender, veJoeToClaim);
        }
    }
}
