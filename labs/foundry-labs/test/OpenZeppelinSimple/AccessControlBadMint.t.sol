// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/OpenZeppelinSimple/AccessControlBadMint.sol";

contract AccessControlBadMintTest is Test {
    AccessControlBadMint token;

    address alice = address(0xA11CE);

    function setUp() public {
        token = new AccessControlBadMint();
    }

    function test_Bad_noOneCanMint_initially() public {
        // 部署者也没有 MINTER_ROLE，所以 mint 必然 revert
        vm.expectRevert();
        token.mint(alice, 100);
    }

    function test_Bad_adminCanGrant_thenMintWorks() public {
        // 证明“只有 admin 能修复”，并且角色链路理解正确
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(alice, 100);

        assertEq(token.balanceOf(alice), 100);
        assertEq(token.totalSupply(), 100);
    }
}
