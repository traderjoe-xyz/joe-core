
// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./VeJoeToken.sol";

contract VeJoeStaking is 
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    struct UserInfo {
        uint256 balance; // Amount of JOE currently staked by user
        uint256 lastRewardTimestamp; // Time of last veJOE claim, or time of first deposit if user 
        // has not claimed any veJOE yet
    }

    IERC20Upgradeable public joe;
    VeJoeToken public veJoe;
  
    /// @notice Rate of veJOE generated per sec per JOE staked
    uint256 public baseGenerationRate;
  
    /// @notice Boosted rate of veJOE generated per sec per JOE staked
    uint256 public boostedGenerationRate;
  
    /// @notice Amount of JOE required to deposit in order for user to start
    /// receiving boosted benefits, in parts per 100. 
    /// @dev Specifically, user has to deposit at least `boostedThreshold/100 * totalJoeStaked` JOE.
    /// The only exception is the user will also receive boosted benefits if its their first
    /// time staking.
    uint256 public boostedThreshold;
  
    /// @notice The length of time a user receives boosted benefits
    uint256 public boostedDuration;

    mapping(address => UserInfo) public userInfos;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);
  
    /// @notice Initialize with needed parameters
    /// @param _joe Address of the JOE token contract
    /// @param _rJoe Address of the rJOE token contract
    /// @param _rJoePerSec Number of rJOE tokens created per second
    function initialize(
        IERC20Upgradeable _joe,
        VeJoeToken _veJoe;
        uint256 _baseGenerationRate,
        uint256 _boostedGenerationRate,
        uint256 _boostedThreshold,
        uint256 _boostedDuration
    ) public initializer {
        require(address(_joe) != address(0), "VeJoeStaking: unexpected zero address for _joe");
        require(address(_veJoe) != address(0), "VeJoeStaking: unexpected zero address for _veJoe");
        require(
            _boostedGenerationRate > _baseGenerationRate, 
            "VeJoeStaking: expected _boostedGenerationRate to be greater than _baseGenerationRate"
        );
        require(
            _boostedThreshold <= 100, 
            "VeJoeStaking: expected _boostedThreshold to be less than or equal to 100"
        );
  
        __Ownable_init();
        __ReentrancyGuard_init_unchained();

        joe = _joe;
        veJoe = _veJoe; 
        baseGenerationRate = _baseGenerationRate;
        boostedGenerationRate = _boostedGenerationRate;
        boostedThreshold = _boostedThreshold;
        boostedDuration = _boostedDuration;
    }

    /// @notice Set baseGenerationRate
    /// @param _baseGenerationRate the new baseGenerationRate
    function setBaseGenerationRate(uint256 _baseGenerationRate) external onlyOwner {
        require(
            _baseGenerationRate < boostedGenerationRate, 
            "VeJoeStaking: expected new _baseGenerationRate to be less than boostedGenerationRate"
        );
        baseGenerationRate = _baseGenerationRate;
    }

    /// @notice Set boostedGenerationRate
    /// @param _boostedGenerationRate the new boostedGenerationRate
    function setBoostedGenerationRate(uint256 _boostedGenerationRate) external onlyOwner {
        require(
            _boostedGenerationRate > baseGenerationRate, 
            "VeJoeStaking: expected new _boostedGenerationRate to be greater than baseGenerationRate"
        );
        boostedGenerationRate = _boostedGenerationRate;
    }

    /// @notice Set boostedThreshold
    /// @param _boostedThreshold the new boostedThreshold
    function setBoostedThreshold(uint256 _boostedThreshold) external onlyOwner {
        require(
            _boostedThreshold <= 100, 
            "VeJoeStaking: expected new _boostedThreshold to be less than or equal to 100"
        );
        boostedGenerationRate = _boostedGenerationRate;
    }

    /// @notice Set boostedDuration
    /// @param _boostedDuration the new boostedDuration
    function setBoostedDuration(uint256 _boostedDuration) external onlyOwner {
        boostedDuration = _boostedDuration;
    }

    /// @notice Deposits JOE to start staking for veJOE
    /// @param _amount the amount of JOE to deposit
    function deposit(uint256 _amount) external {
        require(_amount > 0, "VeJoeStaking: expected deposit amount to be greater than zero");

        if (getUserHasStakedJoe(msg.sender)) {
            // If user already has staked JOE, we first send any pending veJOE
            // and then increase their balance
            _claim(msg.sender);
            userInfos[msg.sender].balance += _amount;
        } else {
            // Otherwise we just create a new entry for the user in `userInfos`
            userInfos[msg.sender].balance = _amount;
            userInfos[msg.sender].lastRewardTimestamp = block.timestamp;
        }

        joe.safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _amount);
    }

    /// @notice Claim any pending veJOE
    function claim() external {
        require(getUserHasStakedJoe(msg.sender), "VeJoeStaking: cannot claim any veJOE when no JOE is staked");
        _claim(msg.sender);
    }

    /// @notice Get the pending amount of veJOE for a given user
    /// @param _user The user to lookup
    /// @return The number of pending veJOE tokens for `_user`
    function pendingVeJoe(address _user) external view returns (uint256) {
        if (!getUserHasStakedJoe(_user) || block.timestamp == user.lastRewardTimestamp) {
          return 0;
        }

        UserInfo storage user = userInfos[_user];

        uint256 secondsElapsed = block.timestamp - user.lastRewardTimestamp;
        uint256 accVeJoePerJoe = secondsElapsed * user.balance;

        return user.balance * accVeJoePerJoe;
    }

    /// @dev Helper to claim any pending veJOE
    function _claim() private {
        uint256 veJoeToClaim = pendingVeJoe(msg.sender);

        // Update user's last reward timestamp
        userInfos[msg.sender].lastRewardTimestamp = block.timestamp;

        if (veJoeToClaim > 0) {
            veJoe.mint(msg.sender, veJoeToClaim);
            emit Claimed(_addr, veJoeToClaim);
        }
    }

    /// @notice Checks to see if a given user currently has staked JOE
    /// @param _user the user address to check
    /// @return whether `_user` currently has staked JOE
    function getUserHasStakedJoe(address _user) public view override returns (bool) {
        return userInfos[_user].balance > 0;
    }
  
}