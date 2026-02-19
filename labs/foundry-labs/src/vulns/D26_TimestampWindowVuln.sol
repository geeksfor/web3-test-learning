// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice 演示“时间依赖”风险：最后几秒内折扣价 vs 原价，差异巨大。
/// 出块者可在允许范围内偏移 timestamp，把交易卡到“有利的那一边”。
contract D26_TimestampWindowVuln {
    uint256 public immutable saleStart;
    uint256 public immutable saleEnd;

    uint256 public constant FULL_PRICE = 1 ether;
    uint256 public constant DISCOUNT_PRICE = 0.1 ether;

    event Bought(address indexed buyer, uint256 paid, uint256 ts);

    constructor(uint256 _saleStart, uint256 _saleEnd) {
        require(_saleStart < _saleEnd, "bad range");
        saleStart = _saleStart;
        saleEnd = _saleEnd;
    }

    /// @notice 规则：活动期间可买；如果在最后 10 秒内买，享受超低折扣
    function buy() external payable {
        require(
            block.timestamp >= saleStart && block.timestamp <= saleEnd,
            "not in sale"
        );
        // ⚠️ 漏洞点：窗口非常窄（最后10秒），且价格差距巨大
        uint256 price = (block.timestamp >= saleEnd - 10)
            ? DISCOUNT_PRICE
            : FULL_PRICE;
        require(msg.value == price, "wrong price");
        emit Bought(msg.sender, msg.value, block.timestamp);
    }
}
