// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice D16 修复版：用 AccessControl 做角色分权
/// - CONFIG_ROLE: setTreasury / setFee
/// - FINANCE_ROLE: withdrawFees
/// - PAUSER_ROLE : pause / unpause
/// - DEFAULT_ADMIN_ROLE: 管理角色授权/回收
contract AccessControlRolesFixed is AccessControl {
    // ---- roles ----
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");
    bytes32 public constant FINANCE_ROLE = keccak256("FINANCE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ---- state ----
    address public treasury;
    uint256 public feeBps; // 100 = 1%
    bool public paused;

    uint256 public feesAccrued;

    // ---- events ----
    event TreasuryChanged(
        address indexed oldTreasury,
        address indexed newTreasury
    );
    event FeeChanged(uint256 oldFeeBps, uint256 newFeeBps);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event Paid(address indexed payer, uint256 amountIn, uint256 fee);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // ---- errors ----
    error InvalidTreasury();
    error InvalidFeeBps(uint256 feeBps);
    error PausedError();
    error TransferFailed();

    constructor(
        address admin,
        address initialTreasury,
        uint256 initialFeeBps,
        address config,
        address finance,
        address pauser
    ) {
        if (admin == address(0)) revert InvalidTreasury();
        if (initialTreasury == address(0)) revert InvalidTreasury();
        if (initialFeeBps > 1000) revert InvalidFeeBps(initialFeeBps);

        treasury = initialTreasury;
        feeBps = initialFeeBps;
        paused = false;

        // admin 负责授权/回收角色
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        // 分权角色
        _grantRole(CONFIG_ROLE, config);
        _grantRole(FINANCE_ROLE, finance);
        _grantRole(PAUSER_ROLE, pauser);
    }

    // ------------------------
    // Guarded admin functions
    // ------------------------
    function setTreasury(address newTreasury) external onlyRole(CONFIG_ROLE) {
        if (newTreasury == address(0)) revert InvalidTreasury();
        address old = treasury;
        treasury = newTreasury;
        emit TreasuryChanged(old, newTreasury);
    }

    function setFee(uint256 newFeeBps) external onlyRole(CONFIG_ROLE) {
        if (newFeeBps > 1000) revert InvalidFeeBps(newFeeBps);
        uint256 old = feeBps;
        feeBps = newFeeBps;
        emit FeeChanged(old, newFeeBps);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function withdrawFees() external onlyRole(FINANCE_ROLE) {
        uint256 amount = feesAccrued;
        feesAccrued = 0;

        (bool ok, ) = treasury.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit FeesWithdrawn(treasury, amount);
    }

    // ------------------------
    // Business function
    // ------------------------
    function pay() external payable {
        if (paused) revert PausedError();
        uint256 fee = (msg.value * feeBps) / 10_000;
        feesAccrued += fee;
        emit Paid(msg.sender, msg.value, fee);
    }

    receive() external payable {}
}
