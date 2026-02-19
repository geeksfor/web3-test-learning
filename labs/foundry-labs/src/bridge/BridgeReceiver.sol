// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../mocks/lz/ILZReceiver.sol";

contract BridgeReceiver is ILZReceiver {
    error NotEndpoint();
    error UntrustedSource(uint16 srcChainId, address srcApp);
    error AlreadyProcessed(bytes32 messageId);

    address public immutable endpoint;

    // 白名单：srcChainId + srcApp
    mapping(uint16 => mapping(address => bool)) public trusted;

    // 去重：messageId
    mapping(bytes32 => bool) public processed;

    event Received(
        uint16 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes32 messageId
    );

    constructor(address _endpoint) {
        endpoint = _endpoint;
    }

    function setTrusted(uint16 srcChainId, address srcApp, bool ok) external {
        // demo：省略权限控制，真实项目要 onlyOwner / role
        trusted[srcChainId][srcApp] = ok;
    }

    function lzReceive(
        uint16 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload,
        bytes32 messageId
    ) external override {
        if (msg.sender != endpoint) revert NotEndpoint();
        if (!trusted[srcChainId][srcApp])
            revert UntrustedSource(srcChainId, srcApp);
        if (processed[messageId]) revert AlreadyProcessed(messageId);

        processed[messageId] = true;

        // 业务执行（演示：只解码，不做 token mint）
        (address to, uint256 amount) = abi.decode(payload, (address, uint256));
        // ... credit(to, amount)

        emit Received(srcChainId, srcApp, nonce, messageId);
    }
}
