// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @title Cliff
 * @dev A token holder contract that can release its token balance with a cliff period.
 * Optionally revocable by the owner.
 */
contract Cliff {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 public constant SECONDS_PER_MONTH = 30 days;

    event Released(uint256 amount);

    // beneficiary of tokens after they are released
    address public immutable beneficiary;
    IERC20 public immutable token;

    uint256 public immutable cliffInMonths;
    uint256 public immutable startTimestamp;
    uint256 public released;

    /**
     * @dev Creates a cliff contract that locks its balance of any ERC20 token and
     * only allows release to the beneficiary once the cliff has passed.
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _cliffInMonths duration in months of the cliff in which tokens will begin to vest
     */
    constructor(
        address _token,
        address _beneficiary,
        uint256 _startTimestamp,
        uint256 _cliffInMonths
    ) public {
        require(_beneficiary != address(0), "Cliff: Beneficiary cannot be empty");

        token = IERC20(_token);
        beneficiary = _beneficiary;
        cliffInMonths = _cliffInMonths;
        startTimestamp = _startTimestamp == 0 ? blockTimestamp() : _startTimestamp;
    }

    /**
     * @notice Transfers vested tokens to beneficiary.
     */
    function release() external {
        uint256 vested = vestedAmount();
        require(vested > 0, "Cliff: No tokens to release");

        released = released.add(vested);
        token.safeTransfer(beneficiary, vested);

        emit Released(vested);
    }

    /**
     * @dev Calculates the amount that has already vested but hasn't been released yet.
     */
    function vestedAmount() public view returns (uint256) {
        if (blockTimestamp() < startTimestamp) {
            return 0;
        }

        uint256 elapsedTime = blockTimestamp().sub(startTimestamp);
        uint256 elapsedMonths = elapsedTime.div(SECONDS_PER_MONTH);

        if (elapsedMonths < cliffInMonths) {
            return 0;
        } else {
            return token.balanceOf(address(this));
        }
    }

    function blockTimestamp() public view virtual returns (uint256) {
        return block.timestamp;
    }
}
