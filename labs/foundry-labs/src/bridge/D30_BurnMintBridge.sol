// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./D30_SimpleMintBurnERC20.sol";
import "../mocks/lz/ILZReceiver.sol";
import "../mocks/lz/MockLZEndpoint.sol";

contract BurnMintBridge is ILZReceiver {
    SimpleMintBurnERC20 public immutable token;
    MockLZEndpoint public immutable endpoint;

    // 白名单：srcChainId + srcApp
    mapping(uint16 => mapping(address => bool)) public trusted;

    error NotEndpoint();
    error UntrustedSource(uint16 srcChainId, address srcApp);

    constructor(SimpleMintBurnERC20 _token, MockLZEndpoint _endpoint) {
        token = _token;
        endpoint = _endpoint;
    }

    function setTrusted(uint16 srcChainId, address srcApp, bool ok) external {
        // demo：省略权限控制，真实项目要 onlyOwner / role
        trusted[srcChainId][srcApp] = ok;
    }

    function bridge(
        uint16 dstChainId,
        address dstApp,
        address to,
        uint256 amount
    ) external {
        // 这里为了简化：直接 burn msg.sender 的余额
        token.burn(msg.sender, amount);
        bytes memory payload = abi.encode(to, amount);
        endpoint.send(dstChainId, dstApp, payload);
    }

    function lzReceive(
        uint16 srcChainId,
        address srcApp,
        uint64 /*nonce*/,
        bytes calldata payload,
        bytes32 /*messageId*/
    ) external override {
        if (msg.sender != address(endpoint)) revert NotEndpoint();
        if (!trusted[srcChainId][srcApp])
            revert UntrustedSource(srcChainId, srcApp);

        // 业务执行（演示：只解码，不做 token mint）
        (address to, uint256 amount) = abi.decode(payload, (address, uint256));
        // ... credit(to, amount)
        token.mint(to, amount);
    }
}
