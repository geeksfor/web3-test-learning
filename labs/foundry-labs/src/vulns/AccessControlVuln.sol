// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice D16 示例：故意缺少权限控制（Missing Access Control）
/// - setTreasury / setFee / pause / unpause / withdrawFees 全都缺少权限控制
/// - 业务：pay() 会收取 fee 并累计到 feesAccrued；withdrawFees() 把手续费转给 treasury
contract AccessControlVuln {
    // ---- config/state ----
    address public owner; // 这里虽然有 owner，但我们故意不使用它来做权限控制
    address public treasury; // 手续费/收入收款地址
    uint256 public feeBps; // fee in basis points (bps), 100 = 1%
    bool public paused; // 简化版 pause 开关

    uint256 public feesAccrued; // 累计手续费（留在合约里，等待提取）

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

    error InvalidTreasury();
    error InvalidFeeBps(uint256 feeBps);
    error PausedError();
    error TransferFailed();

    constructor(address _treasury, uint256 _feeBps) {
        owner = msg.sender;
        treasury = _treasury;
        feeBps = _feeBps;
        paused = false;
    }

    // ============================================================
    // VULNERABLE FUNCTIONS (Missing Access Control)
    // ============================================================

    /// @notice 漏洞：任何人都能改 treasury，后续收入可被劫持
    function setTreasury(address newTreasury) external {
        if (newTreasury == address(0)) revert InvalidTreasury();
        address old = treasury;
        treasury = newTreasury;
        emit TreasuryChanged(old, newTreasury);
    }

    /// @notice 漏洞：任何人都能改 fee，可导致抽税/DoS/经济模型破坏
    /// @dev 示例限制 fee <= 1000 bps(10%)，真实项目按需
    function setFee(uint256 newFeeBps) external {
        if (newFeeBps > 1000) revert InvalidFeeBps(newFeeBps);
        uint256 old = feeBps;
        feeBps = newFeeBps;
        emit FeeChanged(old, newFeeBps);
    }

    /// @notice 漏洞：任何人都能 pause，可能导致协议被恶意停机（DoS）
    function pause() external {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice 漏洞：任何人都能 unpause，可能破坏官方止损措施
    function unpause() external {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice 漏洞：任何人都能提走累计手续费（配合 setTreasury 就是直接盗款）
    function withdrawFees() external {
        uint256 amount = feesAccrued;
        feesAccrued = 0;
        (bool ok, ) = treasury.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit FeesWithdrawn(treasury, amount);
    }

    // ============================================================
    // Example business function (optional)
    // 用来体现 fee / treasury 的“后续影响”，更像真实协议
    // ============================================================

    /// @notice 一个示例函数：收取 msg.value 的 fee，并把 fee “记账”给 treasury（这里只做示意）
    /// @dev 为了简单，这里不真的转账到 treasury，而是把 fee 留在合约里；你也可以改成直接转
    function pay() external payable {
        if (paused) revert PausedError();
        uint256 fee = (msg.value * feeBps) / 10_000;
        feesAccrued += fee;
        emit Paid(msg.sender, msg.value, fee);
    }

    receive() external payable {}
}
