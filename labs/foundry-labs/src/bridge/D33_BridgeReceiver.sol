// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MessageIdLib} from "./MessageIdLib.sol";

interface IMintable {
    function mint(address to, uint256 amount) external;
}

contract BridgeReceiver {
    using MessageIdLib for uint16;

    error Replay(bytes32 messageId);

    mapping(bytes32 => bool) public processed;

    uint16 public immutable dstChainId; // 目标链 id（本链）
    IMintable public immutable token;

    constructor(uint16 _dstChainId, IMintable _token) {
        dstChainId = _dstChainId;
        token = _token;
    }

    // 模拟跨链 Endpoint 调用入口
    function lzReceive(
        uint16 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload
    ) external {
        bytes32 mid = MessageIdLib.compute(
            srcChainId,
            srcApp,
            dstChainId,
            address(this), // dstApp = 当前接收合约
            nonce,
            payload
        );

        if (processed[mid]) revert Replay(mid);
        processed[mid] = true;

        (address to, uint256 amount) = abi.decode(payload, (address, uint256));
        token.mint(to, amount);
    }
}
