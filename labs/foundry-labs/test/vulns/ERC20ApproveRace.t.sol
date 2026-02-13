// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/erc20/SimpleERC20ApproveRace.sol";
import "../../src/erc20/AllowanceSpender.sol";

contract ERC20ApproveRaceTest is Test {
    SimpleERC20ApproveRace token;
    AllowanceSpender spender;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new SimpleERC20ApproveRace();
        spender = new AllowanceSpender(token);

        token.mint(alice, 1_000 ether);
    }

    function test_race_approve_change_gets_sandwiched() public {
        // 1) Alice 初始授权 spender 100
        vm.prank(alice);
        token.approve(address(spender), 100 ether);
        assertEq(token.allowance(alice, address(spender)), 100 ether);

        // 2) Alice 想把额度改小到 50（覆盖式 approve）
        // ---- 夹击模拟：spender 在这笔 approve 之前先花掉旧额度 100 ----
        // 2) Alice 想把额度改小到 50（覆盖式 approve）
        // ---- 夹击模拟：spender 在这笔 approve 之前先花掉旧额度 100 ----
        vm.prank(address(spender));
        spender.spendFrom(alice, bob, 100 ether);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.allowance(alice, address(spender)), 0);

        // 3) 然后 Alice 的 approve(50) 才上链
        vm.prank(alice);
        token.approve(address(spender), 50 ether);
        assertEq(token.allowance(alice, address(spender)), 50 ether);

        // 4) spender 再花掉 50
        vm.prank(address(spender));
        spender.spendFrom(alice, bob, 50 ether);

        // ✅ 最终 spender 总共花掉 150（本来 Alice 的意图是“总共只让花 50”）
        assertEq(token.balanceOf(bob), 150 ether);
    }

    function test_fixA_approve_zero_then_set_new() public {
        // 初始授权 100
        vm.prank(alice);
        token.approve(address(spender), 100 ether);

        // Alice 第一笔：清零
        vm.prank(alice);
        token.approve(address(spender), 0);
        assertEq(token.allowance(alice, address(spender)), 0);

        // spender 这时想花 100 —— 必须失败
        vm.expectRevert(); // InsufficientAllowance
        vm.prank(address(spender));
        spender.spendFrom(alice, bob, 100 ether);

        // Alice 第二笔：设置新额度 50
        vm.prank(alice);
        token.approve(address(spender), 50 ether);

        // spender 最多只能花 50
        vm.prank(address(spender));
        spender.spendFrom(alice, bob, 50 ether);
        assertEq(token.allowance(alice, address(spender)), 0);
    }

    function test_fixB_decreaseAllowance_handles_race() public {
        vm.prank(alice);
        token.approve(address(spender), 100 ether);

        // spender 夹击先花 60
        vm.prank(address(spender));
        spender.spendFrom(alice, bob, 60 ether);
        assertEq(token.allowance(alice, address(spender)), 40 ether);

        // Alice 还以为自己还能从 100 直接降到 50（减 50）
        // 但实际 cur=40，decreaseAllowance(50) 应当失败，避免错误状态
        vm.expectRevert(bytes("decrease below zero"));
        vm.prank(alice);
        token.decreaseAllowance(address(spender), 50 ether);

        // Alice 正确做法：把剩余 40 降到 0（减 40） 或者直接重算目标差值
        vm.prank(alice);
        token.decreaseAllowance(address(spender), 40 ether);
        assertEq(token.allowance(alice, address(spender)), 0);
    }
}
