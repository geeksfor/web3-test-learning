// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract AccessControlGoodMint is AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor(address admin, address initialMinter) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, initialMinter);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
