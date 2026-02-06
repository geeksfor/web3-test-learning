// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract AccessControlBadMint is AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor() {
        // ✅ 只设置了 admin，但 ❌ 没给任何人 MINTER_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
