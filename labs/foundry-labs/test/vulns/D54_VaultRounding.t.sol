// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SimpleERC20, VaultRoundingVuln, VaultRoundingFixed} from "../../src/vulns/D54_VaultRounding.sol";

contract D54_VaultRounding_Test is Test {
    SimpleERC20 token;
    VaultRoundingVuln vuln;
    VaultRoundingFixed fixedVault;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address attacker = makeAddr("attacker");

    function setUp() public {
        token = new SimpleERC20();
        vuln = new VaultRoundingVuln(token);
        fixedVault = new VaultRoundingFixed(token);

        // 初始资金
        token.mint(alice, 100 ether);
        token.mint(bob, 10 ether);
        token.mint(attacker, 1_000_000 ether);

        vm.prank(alice);
        token.approve(address(vuln), type(uint256).max);
        vm.prank(alice);
        token.approve(address(fixedVault), type(uint256).max);

        vm.prank(bob);
        token.approve(address(vuln), type(uint256).max);
        vm.prank(bob);
        token.approve(address(fixedVault), type(uint256).max);
    }

    /// 1) 漏洞复现：donation 之后，小额 deposit -> shares=0，但资产被吞
    function test_vuln_smallDeposit_afterDonation_mintsZeroShares_butTakesAssets() public {
        // Alice 先存 100，建立 supply
        vm.prank(alice);
        vuln.deposit(100 ether, alice);
        assertEq(vuln.totalSupply(), 100 ether);

        // Attacker 直接 donate 大量 token 到 vault（绕过 deposit）
        vm.prank(attacker);
        token.transfer(address(vuln), 1_000_000 ether);

        // Bob 小额存 1 wei（极小）
        uint256 bobAssetsBefore = token.balanceOf(bob);
        uint256 bobSharesBefore = vuln.balanceOf(bob);

        vm.prank(bob);
        vuln.deposit(1, bob);

        uint256 bobAssetsAfter = token.balanceOf(bob);
        uint256 bobSharesAfter = vuln.balanceOf(bob);

        // ✅ 资产减少了
        assertEq(bobAssetsBefore - bobAssetsAfter, 1);
        // ✅ 但 shares 没增加（被吞）
        assertEq(bobSharesAfter, bobSharesBefore);
    }

    /// 2) 修复回归：同样场景必须 revert（避免吞资产）
    function test_fixed_smallDeposit_afterDonation_revertsZeroShares() public {
        vm.prank(alice);
        fixedVault.deposit(100 ether, alice);

        vm.prank(attacker);
        token.transfer(address(fixedVault), 1_000_000 ether);

        vm.prank(bob);
        vm.expectRevert();
        fixedVault.deposit(1, bob);
    }

    /// 3) 额外回归：正常比例下，小额 deposit 不该误伤（仍能成功）
    function test_fixed_smallDeposit_normalRatio_ok() public {
        // 没 donation，比例正常
        vm.prank(alice);
        fixedVault.deposit(100 ether, alice);

        uint256 bobAssetsBefore = token.balanceOf(bob);

        vm.prank(bob);
        fixedVault.deposit(1 ether, bob);

        assertEq(token.balanceOf(bob), bobAssetsBefore - 1 ether);
        assertGt(fixedVault.balanceOf(bob), 0);
    }
}
