// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/vulns/D15_Reentrancy_Vuln.sol";
import "../../src/vulns/D15_Reentrancy_Exploit.sol";

contract D15ReentrancyTest is Test {
    address victim = address(0xBEEF);
    address attackerEOA = address(0xA11CE);

    function setUp() public {
        vm.deal(victim, 100 ether);
        vm.deal(attackerEOA, 10 ether);
    }

    function test_Exploit_Drains_VulnerableBank() public {
        MiniBankVuln bank = new MiniBankVuln();
        // 受害者先存很多钱（形成“可被掏空”的资金池）
        vm.prank(victim);
        bank.deposit{value: 50 ether}();
        assertEq(address(bank).balance, 50 ether);

        // 攻击者部署攻击合约
        vm.startPrank(attackerEOA);
        ReentrancyAttacker exp = new ReentrancyAttacker(address(bank));

        // 攻击者只存 1 ether，但可以在 withdraw 时反复重入把池子掏空
        exp.seedAndAttack{value: 1 ether}(1 ether);
        vm.stopPrank();

        // 关键断言：bank 被掏空（或几乎掏空到 0）
        assertEq(address(bank).balance, 0);

        // 攻击合约里至少拿到了受害者的资金（> 1 ether）
        assertGt(address(exp).balance, 1 ether);
    }

    function test_FixedByCEI_ExploitFails() public {
        MiniBankCEI bank = new MiniBankCEI();

        vm.prank(victim);
        bank.deposit{value: 50 ether}();
        assertEq(address(bank).balance, 50 ether);

        vm.startPrank(attackerEOA);
        ReentrancyAttacker exp = new ReentrancyAttacker(address(bank));

        // 这里大概率会在重入时因为余额已先扣掉，后续 withdraw 触发 "insufficient"
        // 由于攻击合约 receive 里会继续调 withdraw，最终整笔交易会 revert（call 栈里 require 失败）
        vm.expectRevert(); // 不绑定字符串，版本差异更稳
        exp.seedAndAttack{value: 1 ether}(1 ether);
        vm.stopPrank();

        // 银行资金仍在
        assertEq(address(bank).balance, 50 ether);
    }

    function test_FixedByReentrancyGuard_ExploitFails() public {
        MiniBankGuarded bank = new MiniBankGuarded();

        vm.prank(victim);
        bank.deposit{value: 50 ether}();
        assertEq(address(bank).balance, 50 ether);

        vm.startPrank(attackerEOA);
        ReentrancyAttacker exp = new ReentrancyAttacker(address(bank));

        // 重入第二次进入 withdraw 会触发 nonReentrant 的 REENTRANT
        vm.expectRevert(); // 或 vm.expectRevert("REENTRANT")
        exp.seedAndAttack{value: 1 ether}(1 ether);
        vm.stopPrank();

        assertEq(address(bank).balance, 50 ether);
    }
}
