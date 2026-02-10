// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "../../src/vulns/AccessControlRolesFixed.sol";

contract AccessControlD16RolesTest is Test {
    address admin = address(0xBEEF);
    address config = address(0xC0FFEE);
    address finance = address(0xC0DE);
    address pauser = address(0xCAFE);

    address alice = address(0xA11CE);
    address attacker = address(0xBAD);
    address treasury = address(0xEEA);

    AccessControlRolesFixed fixedR;

    function setUp() public {
        vm.deal(admin, 100 ether);
        vm.deal(config, 100 ether);
        vm.deal(finance, 100 ether);
        vm.deal(pauser, 100 ether);

        vm.deal(alice, 100 ether);
        vm.deal(attacker, 100 ether);
        vm.deal(treasury, 0 ether);

        fixedR = new AccessControlRolesFixed(
            admin,
            treasury,
            300, // 3%
            config,
            finance,
            pauser
        );
    }

    // ------------------------
    // 未授权必须被拦住
    // ------------------------
    function test_attackerCannotSetTreasury() public {
        vm.startPrank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                fixedR.CONFIG_ROLE()
            )
        );
        fixedR.setTreasury(attacker);
        vm.stopPrank();
        assertEq(fixedR.treasury(), treasury);
    }

    function test_attackerCannotWithdrawFees() public {
        // 先产生 fees
        vm.prank(alice);
        fixedR.pay{value: 10 ether}();
        assertEq(fixedR.feesAccrued(), 0.3 ether);

        // attacker 提取应失败
        vm.startPrank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                fixedR.FINANCE_ROLE()
            )
        );
        fixedR.withdrawFees();
        vm.stopPrank();

        assertEq(fixedR.feesAccrued(), 0.3 ether);
    }

    function test_attackerCannotPause() public {
        vm.startPrank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                fixedR.PAUSER_ROLE()
            )
        );
        fixedR.pause();
        vm.stopPrank();
    }

    // ------------------------
    // 合法角色可以操作
    // ------------------------
    function test_configCanSetTreasuryAndFee() public {
        vm.prank(config);
        fixedR.setTreasury(address(0x1234));
        assertEq(fixedR.treasury(), address(0x1234));

        vm.prank(config);
        fixedR.setFee(500);
        assertEq(fixedR.feeBps(), 500);
    }

    function test_financeCanWithdrawFees_toTreasury() public {
        vm.prank(alice);
        fixedR.pay{value: 10 ether}();
        assertEq(fixedR.feesAccrued(), 0.3 ether);

        uint256 treasuryBefore = treasury.balance;

        vm.prank(finance);
        fixedR.withdrawFees();

        assertEq(treasury.balance, treasuryBefore + 0.3 ether);
        assertEq(fixedR.feesAccrued(), 0);
    }

    function test_pauserCanPause_and_payReverts() public {
        vm.prank(pauser);
        fixedR.pause();
        assertTrue(fixedR.paused());

        vm.prank(alice);
        vm.expectRevert(AccessControlRolesFixed.PausedError.selector);
        fixedR.pay{value: 1 ether}();
    }

    // ------------------------
    // admin 可以调整角色（分权体系的“根”）
    // ------------------------
    function test_adminCanGrantRole_toNewFinance() public {
        address newFinance = address(0xF00D);
        vm.deal(newFinance, 1 ether);

        // admin 授权
        vm.startPrank(admin);
        fixedR.grantRole(fixedR.FINANCE_ROLE(), newFinance);
        vm.stopPrank();
        assertTrue(fixedR.hasRole(fixedR.FINANCE_ROLE(), newFinance));
    }
}
