// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/OpenZeppelinSimple/AccessControlGoodMint.sol";

contract AccessControlGoodMintTest is Test {
    AccessControlGoodMint token;

    address admin = address(0xADAD);
    address minter = address(0xB0B);
    address alice = address(0xA11CE);
    address attacker = address(0xBEEF);

    function setUp() public {
        token = new AccessControlGoodMint(admin, minter);
    }

    function test_Good_minterCanMint() public {
        vm.prank(minter);
        token.mint(alice, 100);

        assertEq(token.balanceOf(alice), 100);
        assertEq(token.totalSupply(), 100);
    }

    function test_Good_nonMinterCannotMint() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.mint(attacker, 1);
    }

    function test_Good_adminCanGrantAndRevokeMinter() public {
        bytes32 minterRole = token.MINTER_ROLE();
        // admin 授权 attacker 为 minter
        vm.prank(admin);
        token.grantRole(minterRole, attacker);

        vm.prank(attacker);
        token.mint(attacker, 10);
        assertEq(token.balanceOf(attacker), 10);

        // admin 撤销 attacker minter 权限
        vm.prank(admin);
        token.revokeRole(minterRole, attacker);

        vm.prank(attacker);
        vm.expectRevert();
        token.mint(attacker, 1);
    }

    function test_Good_nonAdminCannotGrantRole() public {
        bytes32 minterRole = token.MINTER_ROLE();
        vm.prank(attacker);
        vm.expectRevert();
        token.grantRole(minterRole, attacker);
    }
}
