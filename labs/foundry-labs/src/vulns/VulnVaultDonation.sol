// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./D23_MockERC20.sol";

/// @title VulnVaultDonation
/// @notice A deliberately vulnerable vault: totalAssets() uses raw token balance.
///         Anyone can "donate" tokens via transfer, manipulating share price inside the same tx.
/// @dev This is a learning-only vault, not ERC4626-compliant.
contract VulnVaultDonation {
    MockERC20 public immutable asset;

    string public constant name = "VulnVault Shares";
    string public constant symbol = "vSHARE";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    error ZeroAmount();
    error InsufficientShares(address owner, uint256 have, uint256 need);

    constructor(MockERC20 _asset) {
        asset = _asset;
    }

    function totalAssets() public view returns (uint256) {
        // 🚨 VULNERABILITY: manipulable by external transfers ("donations")
        return asset.balanceOf(address(this));
    }

    function previewDeposit(
        uint256 assets
    ) public view returns (uint256 shares) {
        if (assets == 0) return 0;
        uint256 supply = totalSupply;
        uint256 assetsBefore = totalAssets();
        if (supply == 0 || assetsBefore == 0) return assets; // 1:1 init
        // shares = assets * supply / assetsBefore
        shares = (assets * supply) / assetsBefore;
        if (shares == 0) shares = 1; // round up to keep demo simple
    }

    function previewRedeem(
        uint256 shares
    ) public view returns (uint256 assetsOut) {
        if (shares == 0) return 0;
        uint256 supply = totalSupply;
        if (supply == 0) return 0;
        assetsOut = (shares * totalAssets()) / supply;
    }

    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();

        shares = previewDeposit(assets);

        // pull assets
        asset.transferFrom(msg.sender, address(this), assets);

        // mint shares
        totalSupply += shares;
        balanceOf[receiver] += shares;

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assetsOut) {
        if (shares == 0) revert ZeroAmount();

        uint256 bal = balanceOf[owner];
        if (bal < shares) revert InsufficientShares(owner, bal, shares);

        // burn shares
        unchecked {
            balanceOf[owner] = bal - shares;
            totalSupply -= shares;
        }

        assetsOut = previewRedeem(shares);

        // send assets
        asset.transfer(receiver, assetsOut);

        emit Withdraw(msg.sender, receiver, owner, assetsOut, shares);
    }
}
