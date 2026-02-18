// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title D25 Gas Grief Fix: Pagination / Cursor
/// @notice distributeChunk() 每次只处理一部分，避免单笔交易 O(n) 爆炸
contract D25_GasGriefFixed_Pagination {
    address public owner;
    address[] public participants;
    mapping(address => uint256) public credits;

    uint256 public cursor; // 当前处理进度

    error NotOwner();
    error NothingToProcess();

    constructor() {
        owner = msg.sender;
    }

    function register() external {
        participants.push(msg.sender);
    }

    function participantsCount() external view returns (uint256) {
        return participants.length;
    }

    /// @notice 分批处理：最多处理 maxIters 个参与者
    function distributeChunk(uint256 amountEach, uint256 maxIters) external {
        if (msg.sender != owner) revert NotOwner();
        if (cursor >= participants.length) revert NothingToProcess();

        uint256 end = cursor + maxIters;
        if (end > participants.length) end = participants.length;

        for (uint256 i = cursor; i < end; i++) {
            credits[participants[i]] += amountEach;
        }

        cursor = end;
    }

    function resetCursor() external {
        if (msg.sender != owner) revert NotOwner();
        cursor = 0;
    }
}
