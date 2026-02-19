// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ILZReceiver.sol";

contract MockLZEndpoint {
    uint16 public immutable chainId;

    // 目标链 id => 目标链 endpoint 地址（测试里手动 set）
    mapping(uint16 => MockLZEndpoint) public remotes;

    // srcApp => dstChainId => nonce
    mapping(address => mapping(uint16 => uint64)) public outboundNonce;

    struct Packet {
        uint16 srcChainId;
        address srcApp;
        address dstApp;
        uint64 nonce;
        bytes payload;
        bytes32 messageId;
    }

    // 简单队列：dst endpoint 收到的包
    Packet[] public inbox;

    constructor(uint16 _chainId) {
        chainId = _chainId;
    }

    function setRemote(uint16 dstChainId, MockLZEndpoint dstEndpoint) external {
        remotes[dstChainId] = dstEndpoint;
    }

    function send(
        uint16 dstChainId,
        address dstApp,
        bytes calldata payload
    ) external {
        // 由 endpoint 统一生成 nonce（更贴近真实协议）
        uint64 n = ++outboundNonce[msg.sender][dstChainId];

        bytes32 mid = keccak256(abi.encode(chainId, msg.sender, n, payload));

        Packet memory p = Packet({
            srcChainId: chainId,
            srcApp: msg.sender,
            dstApp: dstApp,
            nonce: n,
            payload: payload,
            messageId: mid
        });
        remotes[dstChainId].pushToInbox(p);
    }

    function pushToInbox(Packet memory p) public {
        // 这里不做权限也可以；想更严格可以 require(msg.sender == address(remotes[p.srcChainId]))
        inbox.push(p);
    }

    function inboxLength() external view returns (uint256) {
        return inbox.length;
    }

    function deliverNext(uint256 idx) external {
        Packet memory p = inbox[idx];

        // 关键：由 endpoint 调用 receiver，因此 receiver 内可用 msg.sender 鉴权
        ILZReceiver(p.dstApp).lzReceive(
            p.srcChainId,
            p.srcApp,
            p.nonce,
            p.payload,
            p.messageId
        );
    }
}
