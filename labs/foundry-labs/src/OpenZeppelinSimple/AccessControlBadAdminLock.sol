// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract AccessControlBadAdminLock is AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ❌ 错误：把 MINTER_ROLE 的管理员改成一个“没人拥有”的角色
    // 这样未来任何人都无法 grant/revoke MINTER_ROLE，权限体系被锁死

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        // ❌ 关键错误：MINTER_ROLE 的 admin 不是 DEFAULT_ADMIN_ROLE
        // 而是 GOVERNOR_ROLE，但我们没有给任何人 GOVERNOR_ROLE
        _setRoleAdmin(MINTER_ROLE, GOVERNOR_ROLE);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
