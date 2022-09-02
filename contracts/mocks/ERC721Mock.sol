// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ERC721Mock is ERC721 {
    uint256 tokenOwners;

    constructor(string memory name, string memory symbol) public ERC721(name, symbol) {}

    function mint(address _account) external {
        _mint(_account, tokenOwners);
        tokenOwners += 1;
    }
}
