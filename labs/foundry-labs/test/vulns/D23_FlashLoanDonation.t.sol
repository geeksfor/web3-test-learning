// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/vulns/D23_MockERC20.sol";
import "../../src/vulns/FlashLenderMock.sol";
import "../../src/vulns/VulnVaultDonation.sol";
import "../../src/vulns/AttackDonation.sol";

/// @title D23 FlashLoan impact - donation manipulation demo
/// @notice Shows same-tx manipulation using flash loan to change vault balance => share price distortion => profit.
contract D23_FlashLoanDonation_Test is Test {
    MockERC20 asset;
    FlashLenderMock lender;
    VulnVaultDonation vault;
    AttackDonation attacker;

    address alice = address(0xA11CE);
    address bob = address(0xB0B); // attacker EOA (owner of AttackDonation)

    function setUp() public {
        asset = new MockERC20("Mock USD", "mUSD", 18);
        vault = new VulnVaultDonation(asset);
        lender = new FlashLenderMock(asset, 5); // 5 bps = 0.05% fee

        // Seed lender liquidity
        asset.mint(address(lender), 1_000_000 ether);

        // Alice initial deposit to vault (victim liquidity)
        asset.mint(alice, 1_000 ether);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1_000 ether, alice);
        vm.stopPrank();

        // Deploy attack contract as bob
        vm.prank(bob);
        attacker = new AttackDonation(asset, lender, vault);

        // Attacker gets tiny initial funds to acquire tiny shares
        asset.mint(bob, 1 ether);
        vm.startPrank(bob);
        asset.approve(address(vault), type(uint256).max);
        // deposit 1 => get ~1 share
        vault.deposit(1 ether, address(attacker));
        vm.stopPrank();
    }

    function test_flashloan_donationManipulation_drainsVictimValue() public {
        uint256 vaultBefore = asset.balanceOf(address(vault));
        uint256 aliceShares = vault.balanceOf(alice);
        uint256 aliceRedeemableBefore = vault.previewRedeem(aliceShares);

        // attack
        uint256 flashAmount = 500_000 ether; // big enough to distort share price
        vm.prank(bob);
        attacker.run(flashAmount);

        // attacker profit stays in attacker contract
        uint256 attackerProfit = asset.balanceOf(address(attacker));

        uint256 vaultAfter = asset.balanceOf(address(vault));
        uint256 aliceRedeemableAfter = vault.previewRedeem(aliceShares);

        // ---- Assertions ("操纵前后资产变化") ----
        assertGt(attackerProfit, 0, "attacker should profit");
        assertLt(vaultAfter, vaultBefore, "vault should lose assets");
        assertLt(
            aliceRedeemableAfter,
            aliceRedeemableBefore,
            "victim redeemable value should drop"
        );

        emit log_named_uint("vaultBefore", vaultBefore);
        emit log_named_uint("vaultAfter", vaultAfter);
        emit log_named_uint("attackerProfit", attackerProfit);
        emit log_named_uint("aliceRedeemableBefore", aliceRedeemableBefore);
        emit log_named_uint("aliceRedeemableAfter", aliceRedeemableAfter);
    }
}
