// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMintable {
    function mint(address to, uint256 amount) external;
}

/// @notice 接收端：带 replay protection（processed[messageId]）
contract BridgeReceiverProtected {
    error NotEndpoint(address caller);
    error Replay(bytes32 messageId);

    address public immutable endpoint; // 你的 mock endpoint 地址
    IMintable public immutable token;

    // replay protection
    mapping(bytes32 => bool) public processed;

    event MessageProcessed(
        bytes32 indexed messageId,
        uint32 srcChainId,
        address indexed srcApp,
        uint64 nonce
    );
    event Minted(address indexed to, uint256 amount, bytes32 indexed messageId);

    constructor(address _endpoint, IMintable _token) {
        endpoint = _endpoint;
        token = _token;
    }

    /// @notice endpoint 回调入口（名字你可以按 mock 端点约定改）
    function lzReceive(
        uint32 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload
    ) external {
        if (msg.sender != endpoint) revert NotEndpoint(msg.sender);

        bytes32 messageId = keccak256(
            abi.encode(srcChainId, srcApp, nonce, payload)
        );
        if (processed[messageId]) revert Replay(messageId);

        // ✅ 建议先标记，再做业务（更 CEI）
        processed[messageId] = true;
        emit MessageProcessed(messageId, srcChainId, srcApp, nonce);
        (address to, uint256 amount) = abi.decode(payload, (address, uint256));
        token.mint(to, amount);
        emit Minted(to, amount, messageId);
    }
}
