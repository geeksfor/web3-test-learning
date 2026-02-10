// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/vulns/AccessControlVuln.sol";
import "../../src/vulns/AccessControlFixed.sol";

contract AccessControlD16Test is Test {
    address owner = address(0xBEEF);
    address alice = address(0xA11CE);
    address attacker = address(0xBAD);
    address treasury = address(0xBAEA);

    AccessControlVuln vuln;
    AccessControlFixed fixedC;

    function setUp() public {
        // 让这些地址有钱，方便转账/收款断言
        vm.deal(owner, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(attacker, 100 ether);
        vm.deal(treasury, 0 ether);

        // 部署漏洞合约
        vm.prank(owner);
        vuln = new AccessControlVuln(treasury, 300); // 3%

        // 部署修复合约
        vm.prank(owner);
        fixedC = new AccessControlFixed(treasury, 300); // 3%
    }

    // =========================
    // Part A: 漏洞证明（未授权调用成功）
    // =========================
    function test_VULN_attackerCanStealFees_via_setTreasury_then_withdraw()
        public
    {
        // 1) alice 交费，产生 feesAccrued
        vm.prank(alice);
        vuln.pay{value: 10 ether}();
        // fee = 10 * 3% = 0.3 ether
        assertEq(vuln.feesAccrued(), 0.3 ether);

        // 2) attacker 未授权把 treasury 改成自己
        vm.prank(attacker);
        vuln.setTreasury(attacker);
        assertEq(vuln.treasury(), attacker);

        // 3) attacker 未授权调用 withdrawFees，把钱转到 attacker treasury
        uint256 attackerBalBefore = attacker.balance;
        vm.prank(attacker);
        vuln.withdrawFees();

        // 断言：攻击者余额增加 0.3 ether，且 feesAccrued 清零
        assertEq(attacker.balance, attackerBalBefore + 0.3 ether);
        assertEq(vuln.feesAccrued(), 0);
    }

    function test_VULN_attackerCanPause_DoS() public {
        // attacker 未授权 pause
        vm.prank(attacker);
        vuln.pause();
        assertTrue(vuln.paused());

        // pause 后 pay() 会 revert
        vm.prank(alice);
        vm.expectRevert(AccessControlVuln.PausedError.selector);
        vuln.pay{value: 1 ether}();
    }

    // =========================
    // Part B: 修复回归（未授权必须被拦住，授权仍可用）
    // =========================
    function test_FIXED_attackerCannotSetTreasury() public {
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlFixed.NotOwner.selector,
                attacker
            )
        );
        fixedC.setTreasury(attacker);

        // 状态不变
        assertEq(fixedC.treasury(), treasury);
    }

    function test_FIXED_ownerCanSetTreasury() public {
        vm.prank(owner);
        fixedC.setTreasury(address(0x1234));
        assertEq(fixedC.treasury(), address(0x1234));
    }

    function test_FIXED_attackerCannotWithdrawFees() public {
        // 先产生 fees
        vm.prank(alice);
        fixedC.pay{value: 10 ether}();
        assertEq(fixedC.feesAccrued(), 0.3 ether);

        // attacker withdraw 失败
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlFixed.NotOwner.selector,
                attacker
            )
        );
        fixedC.withdrawFees();

        // feesAccrued 仍然存在
        assertEq(fixedC.feesAccrued(), 0.3 ether);
    }

    function test_FIXED_ownerWithdrawFees_goesToTreasury() public {
        vm.prank(alice);
        fixedC.pay{value: 10 ether}();
        assertEq(fixedC.feesAccrued(), 0.3 ether);

        uint256 treasuryBefore = treasury.balance;

        vm.prank(owner);
        fixedC.withdrawFees();

        assertEq(treasury.balance, treasuryBefore + 0.3 ether);
        assertEq(fixedC.feesAccrued(), 0);
    }

    function test_FIXED_attackerCannotPause() public {
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlFixed.NotOwner.selector,
                attacker
            )
        );
        fixedC.pause();
    }

    function test_FIXED_ownerCanPause_and_payReverts() public {
        vm.prank(owner);
        fixedC.pause();
        assertTrue(fixedC.paused());

        vm.prank(alice);
        vm.expectRevert(AccessControlFixed.PausedError.selector);
        fixedC.pay{value: 1 ether}();
    }
}
