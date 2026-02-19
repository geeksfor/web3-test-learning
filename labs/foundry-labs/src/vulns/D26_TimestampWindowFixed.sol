// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice 修复思路示例：
/// 不做“最后几秒”这种极窄窗口高价值分支；改成离散 epoch（例如按分钟）
/// 让 proposer 微调几秒难以改变结果。
contract D26_TimestampWindowFixed {
    uint256 public immutable saleStart;
    uint256 public immutable saleEnd;

    uint256 public constant FULL_PRICE = 1 ether;
    uint256 public constant DISCOUNT_PRICE = 0.1 ether;

    // 例如：最后 1 分钟都打折（粗粒度），不做“最后10秒”
    uint256 public constant DISCOUNT_WINDOW = 60;

    event Bought(address indexed buyer, uint256 paid, uint256 ts);

    constructor(uint256 _saleStart, uint256 _saleEnd) {
        require(_saleStart < _saleEnd, "bad range");
        saleStart = _saleStart;
        saleEnd = _saleEnd;
    }

    function buy() external payable {
        require(
            block.timestamp >= saleStart && block.timestamp <= saleEnd,
            "not in sale"
        );
        // ✅ 修复点：窗口变粗，不靠“秒级边界”
        uint256 price = (block.timestamp >= saleEnd - DISCOUNT_WINDOW)
            ? DISCOUNT_PRICE
            : FULL_PRICE;

        require(msg.value == price, "wrong price");
        emit Bought(msg.sender, msg.value, block.timestamp);
    }
}
