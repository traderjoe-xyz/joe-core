// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./VeERC20.sol";

interface IBoostedMasterChefJoe {
    function updateBoost(address, uint256) external;
}

/// @title Vote Escrow Joe Token - veJOE
/// @author Trader Joe
/// @notice Infinite supply, used to receive extra farming yields and voting power
contract VeJoeToken is VeERC20("VeJoeToken", "veJOE"), Ownable {
    /// @notice the BoostedMasterChefJoe contract
    IBoostedMasterChefJoe public boostedMasterChef;

    /// @dev Creates `_amount` token to `_to`. Must only be called by the owner (VeJoeStaking)
    /// @param _to The address that will receive the mint
    /// @param _amount The amount to be minted
    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }

    /// @dev Destroys `_amount` tokens from `_from`. Callable only by the owner (VeJoeStaking)
    /// @param _from The address that will burn tokens
    /// @param _amount The amount to be burned
    function burnFrom(address _from, uint256 _amount) external onlyOwner {
        _burn(_from, _amount);
    }

    /// @dev Sets the address of the master chef contract this updates
    /// @param _boostedMasterChef the address of BoostedMasterChefJoe
    function setBoostedMasterChefJoe(address _boostedMasterChef) external onlyOwner {
        // We allow 0 address here if we want to disable the callback operations
        boostedMasterChef = IBoostedMasterChefJoe(_boostedMasterChef);
    }

    function _afterTokenOperation(address _account, uint256 _newBalance) internal override {
        if (address(boostedMasterChef) != address(0)) {
            boostedMasterChef.updateBoost(_account, _newBalance);
        }
    }
}
