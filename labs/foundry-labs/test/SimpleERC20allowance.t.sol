// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleERC20.sol";
/*
alice（token owner）
bob（spender）
carol（receiver）
*/

contract SimpleERC20AllowanceTest is Test {
  SimpleERC20 token;

  address alice = address(0xA11CE);
  address bob = address(0xB0B);
  address carol = address(0xCcc1);

  function setUp() public {
      token = new SimpleERC20();
      token.mint(alice, 100 ether);
  }

  function test_Approve_SetsAllowance_AndEmitsApproval() public {
    // 1) 切换 msg.sender = alice
    vm.prank(alice);

    // 2) 期待下一次调用中发出 Approval(owner=alice, spender=bob, value=50 ether)
    // expectEmit(checkTopic1, checkTopic2, checkTopic3, checkData)
    // Approval 只有 2 个 indexed：owner, spender；没有 topic3
    vm.expectEmit(true, true, false, true);
    emit SimpleERC20.Approval(alice, bob, 50 ether);

    // 3) 调用 approve
    bool ok = token.approve(bob, 50 ether);
    assertTrue(ok);

    // 4) 断言 allowance 改对了
    assertEq(token.allowance(alice, bob), 50 ether);
  }

  function test_transferFrom_success_balance_allowance_and_events() public {
    // 1) alice approve bob 40
    vm.prank(alice);
    token.approve(bob, 40 ether);
    assertEq(token.allowance(alice, bob), 40 ether);

    // 2) 事件期望：先 Approval(alice, bob, 30) 再 Transfer(alice, carol, 10)
    // 注意：expectEmit 必须写在触发事件的调用之前
    vm.expectEmit(true, true, false, true);
    emit SimpleERC20.Approval(alice, bob, 30 ether);

    vm.expectEmit(true, true, false, true);
    emit SimpleERC20.Transfer(alice, carol, 10 ether);

    // 3) bob transferFrom(alice -> carol, 10)
    vm.prank(bob);
    bool ok = token.transferFrom(alice, carol, 10 ether);
    assertTrue(ok);

    // 4) 断言：余额与 allowance 变化
    assertEq(token.balanceOf(alice), 90 ether);
    assertEq(token.balanceOf(carol), 10 ether);
    assertEq(token.allowance(alice, bob), 30 ether);
  }

  function test_transferFrom_reverts_whenAllowanceInsufficient() public {
    // 1) alice approve bob 5
    vm.prank(alice);
    token.approve(bob, 5 ether);
    assertEq(token.allowance(alice, bob), 5 ether);

    // 2) bob 尝试从 alice 转 6 给 carol —— 应该 revert: InsufficientAllowance(bob, 5, 6)
    vm.expectRevert(abi.encodeWithSelector(SimpleERC20.InsufficientAllowance.selector, bob, 5 ether, 6 ether));

    vm.prank(bob);
    token.transferFrom(alice, carol, 6 ether);

    // 3) 验证所有余额状态不变
    assertEq(token.balanceOf(alice), 100 ether);
    assertEq(token.balanceOf(carol), 0 ether);
    assertEq(token.allowance(alice, bob), 5 ether);
  }

  function test_transferFrom_RevertWhenBalanceInsufficient_EvenIfAllowanceEnough() public {
    // 1) alice approve bob 200
    vm.prank(alice);
    token.approve(bob, 200 ether);
    assertEq(token.allowance(alice, bob), 200 ether);

    // 记录调用前状态
    uint256 aliceBalBefore = token.balanceOf(alice);
    uint256 carolBalBefore = token.balanceOf(carol);
    uint256 allowanceBefore = token.allowance(alice, bob);

    // 2) bob给carol转150，此时会发生revert
    vm.prank(bob);
    vm.expectRevert();
    token.transferFrom(alice, carol, 150 ether);

    // 3) revert 后，状态必须不变（EVM 回滚）
    assertEq(token.balanceOf(alice), aliceBalBefore, "alice balance should not change");
    assertEq(token.balanceOf(carol), carolBalBefore, "carol balance should not change");
    assertEq(token.allowance(alice, bob), allowanceBefore, "allowance should not change");

  }

  function test_InfiniteAllowance_DoesNotDecrease_AndEmitsOnlyTransferForSpend() public {
    // 1) alice 授权 bob 为无限额度
    vm.prank(alice);
    token.approve(bob, type(uint256).max);

    // 2) bob 用 transferFrom 花 10 ether
    uint256 amount = 10 ether;
    // 期望 transferFrom 这次调用里至少会发出 Transfer(alice, carol, amount)
    vm.expectEmit(true, true, false, true);
    emit SimpleERC20.Transfer(alice, carol, amount);
    vm.prank(bob);
    token.transferFrom(alice, carol, amount);

    // 3) 断言余额变化正确
    assertEq(token.balanceOf(alice), 90 ether);
    assertEq(token.balanceOf(carol), 10 ether);

    // 4) 关键断言：allowance 仍为 max（没有扣减）
    assertEq(token.allowance(alice, bob), type(uint256).max);
  }

  function test_ApproveOverwrite_NotAccumulate_EmitsTwice() public {
    // 1) alice approve bob 10
    vm.startPrank(alice);

    // 期望第一次 Approval 事件
    vm.expectEmit(true, true, false, true, address(token));
    emit SimpleERC20.Approval(alice, bob, 10 ether);

    bool ok1 = token.approve(bob, 10 ether);
    assertTrue(ok1);
    assertEq(token.allowance(alice, bob), 10 ether);
    // 2) alice approve bob 20（覆盖写，不是累加到 30)
    // 期望第二次 Approval 事件
    vm.expectEmit(true, true, false, true, address(token));
    emit SimpleERC20.Approval(alice, bob, 20 ether);

    bool ok2 = token.approve(bob, 20 ether);
    assertTrue(ok2);

    // allowance 应该变为 20，而不是 10+20=30
    assertEq(token.allowance(alice, bob), 20 ether);
    vm.stopPrank();

  }
}