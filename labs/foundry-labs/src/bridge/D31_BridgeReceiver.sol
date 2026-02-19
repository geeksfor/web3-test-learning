// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IMintable {
    function mint(address to, uint256 amount) external;
}

contract BridgeReceiver {
    error OnlyEndpoint();
    error AlreadyProcessed(bytes32 messageId);

    address public immutable endpoint;
    IMintable public immutable token;

    mapping(bytes32 => bool) public processed;

    constructor(address _endpoint, address _token) {
        endpoint = _endpoint;
        token = IMintable(_token);
    }

    function computeMessageId(
        uint16 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(srcChainId, srcApp, nonce, payload));
    }

    /// 模拟跨链入口（你也可以命名为 lzReceive / handle / receiveMessage）
    function receiveMessage(
        uint16 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload
    ) external {
        if (msg.sender != endpoint) revert OnlyEndpoint();

        bytes32 messageId = computeMessageId(
            srcChainId,
            srcApp,
            nonce,
            payload
        );
        if (processed[messageId]) revert AlreadyProcessed(messageId);
        // ✅ 先标记再执行（更安全，避免某些回调类场景的重入二次进入）
        processed[messageId] = true;

        (address to, uint256 amount) = abi.decode(payload, (address, uint256));
        token.mint(to, amount);
    }
}
