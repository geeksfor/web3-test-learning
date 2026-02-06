// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/OpenZeppelinSimple/AccessControlBadAdminLock.sol";

contract AccessControlBadAdminLockTest is Test {
    AccessControlBadAdminLock token;

    address admin = address(0xADAD);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new AccessControlBadAdminLock(admin);
    }

    function test_Bad_adminCannotGrantMinter_dueToWrongRoleAdmin() public {
        // admin 拥有 DEFAULT_ADMIN_ROLE，但 MINTER_ROLE 的管理员是 GOVERNOR_ROLE
        // 所以 admin 也无法 grant MINTER_ROLE —— 典型“锁死”配置
        bytes32 minterRole = token.MINTER_ROLE();
        vm.prank(admin);
        vm.expectRevert(); // AccessControlUnauthorizedAccount(...)
        token.grantRole(minterRole, bob);
    }

    function test_Bad_noOneCanEverMint_ifNoMinterExists() public {
        // 没有任何 minter，mint 永远不可用
        vm.expectRevert();
        token.mint(alice, 1);
    }
}
