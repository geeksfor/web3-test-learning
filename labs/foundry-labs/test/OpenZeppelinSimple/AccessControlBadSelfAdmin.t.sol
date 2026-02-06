// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/OpenZeppelinSimple/AccessControlBadSelfAdmin.sol";

contract AccessControlBadSelfAdminTest is Test {
    AccessControlBadSelfAdmin token;

    address admin = address(0xADAD);
    address minter = address(0xB0B);
    address attacker = address(0xBEEF);
    address alice = address(0xA11CE);

    function setUp() public {
        token = new AccessControlBadSelfAdmin(admin, minter);
    }

    function test_Bad_selfAdmin_allowsPrivilegePropagation() public {
        bytes32 minterRole = token.MINTER_ROLE();
        // 1) 初始 minter 当然能 mint
        vm.prank(minter);
        token.mint(alice, 1);
        assertEq(token.balanceOf(alice), 1);

        // 2) ❌ 越权扩张：minter 居然可以直接把 MINTER_ROLE 授给 attacker
        // 因为 MINTER_ROLE 的 admin 被设成了 MINTER_ROLE 自己
        vm.prank(minter);
        token.grantRole(minterRole, attacker);

        // 3) attacker 拿到 minter 后，也能 mint —— 权限扩散成功
        vm.prank(attacker);
        token.mint(attacker, 100);

        assertEq(token.balanceOf(attacker), 100);
        assertEq(token.totalSupply(), 101); // alice 1 + attacker 100
    }

    function test_Bad_adminIsNotNeeded_anymore() public {
        bytes32 minterRole = token.MINTER_ROLE();
        // 甚至不需要 DEFAULT_ADMIN_ROLE 参与，minter 就能不断发放 minter
        vm.prank(minter);
        token.grantRole(minterRole, address(0xCAFE));

        // 证明新地址已经是 minter
        assertTrue(token.hasRole(minterRole, address(0xCAFE)));
    }
}
