// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract FeeCollectorBad {
    // 例如 30 bps = 0.30%
    uint256 public immutable feeBps;
    uint256 public feesAccrued;

    constructor(uint256 _feeBps) {
        feeBps = _feeBps;
    }

    /// @notice 教学：返回扣费后的 amountOut；fee 向下取整
    function takeFee(
        uint256 amount
    ) public returns (uint256 amountOut, uint256 fee) {
        fee = (amount * feeBps) / 10_000; // floor
        feesAccrued += fee;
        amountOut = amount - fee;
    }
}
