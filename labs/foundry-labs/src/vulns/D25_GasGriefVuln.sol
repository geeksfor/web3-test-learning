// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title D25 Gas Grief / Unbounded Loop DoS (Vulnerable)
/// @notice participants 可以无限增长，distribute() 对全量 participants 循环，最终必然 OOG
contract D25_GasGriefVuln {
    address public owner;
    address[] public participants;

    // 模拟“分发结果”写入 storage（每次迭代都会消耗明显 gas）
    mapping(address => uint256) public credits;

    error NotOwner();

    constructor() {
        owner = msg.sender;
    }

    function register() external {
        participants.push(msg.sender);
    }

    function participantsCount() external view returns (uint256) {
        return participants.length;
    }

    /// @notice 关键函数：全量循环 O(n) —— participants 足够大时会永远跑不完
    function distribute(uint256 amountEach) external {
        if (msg.sender != owner) revert NotOwner();

        // O(n) loop —— DoS 根源
        for (uint256 i = 0; i < participants.length; i++) {
            credits[participants[i]] += amountEach;
        }
    }
}
