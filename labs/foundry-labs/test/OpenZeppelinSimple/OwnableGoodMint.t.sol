// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/OpenZeppelinSimple/OwnableGoodMint.sol";

contract OwnableGoodMintTest is Test {
    OwnableGoodMint token;

    address alice = address(0xA11CE);
    address attacker = address(0xBEEF);
    address bob = address(0xBEE);

    function setUp() public {
        token = new OwnableGoodMint(alice);
        // owner 默认是部署者（本测试合约）
    }

    function test_Good_ownerCanMint() public {
        vm.prank(alice);
        token.mint(alice, 100);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.totalSupply(), 100);
    }

    function test_Good_nonOwnerCannotMint() public {
        uint256 amount = 100;

        // 攻击者 mint 给自己失败
        vm.prank(attacker);
        vm.expectRevert();
        token.mint(attacker, amount);
    }

    function test_Good_transferOwnership_changesAuthority() public {
        // 把 owner 转给 bob
        vm.prank(alice);
        token.transferOwnership(bob);

        // 原 owner（本合约）不再能 mint
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1);

        // 新 owner bob 可以 mint
        vm.prank(bob);
        token.mint(bob, 100);
        assertEq(token.balanceOf(bob), 100);
    }
}
