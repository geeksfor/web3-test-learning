// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/mocks/lz/MockLZEndpoint.sol";
import "../../src/bridge/BridgeSender.sol";
import "../../src/bridge/BridgeReceiver.sol";

contract D29_CrossChainMessageModel_Test is Test {
    MockLZEndpoint epA;
    MockLZEndpoint epB;

    BridgeSender senderA;
    BridgeReceiver receiverB;

    uint16 constant CHAIN_A = 101;
    uint16 constant CHAIN_B = 102;

    /// 这个user是用来做什么的呢？
    address user = address(0xA11CE);

    function setUp() public {
        epA = new MockLZEndpoint(CHAIN_A);
        epB = new MockLZEndpoint(CHAIN_B);

        epA.setRemote(CHAIN_B, epB);
        epB.setRemote(CHAIN_A, epA);

        senderA = new BridgeSender(epA);
        receiverB = new BridgeReceiver(address(epB));

        // 建立白名单：允许来自 A 链的 senderA
        receiverB.setTrusted(CHAIN_A, address(senderA), true);
    }

    function test_deliver_ok_and_processed() public {
        senderA.bridge(CHAIN_B, address(receiverB), user, 100);
        assertEq(epB.inboxLength(), 1);

        // 投递（由 epB 调用 receiverB.lzReceive）
        epB.deliverNext(0);

        // 你可以再加：检查 receiverB.processed(messageId) == true
        // 这里为了拿 messageId，可在 MockEndpoint 增加 getInbox(idx) view 返回 Packet
    }

    function test_replay_same_packet_reverts() public {
        senderA.bridge(CHAIN_B, address(receiverB), user, 100);
        epB.deliverNext(0);

        // 第二次投递同一个 idx（同一个 messageId）必须 revert
        vm.expectRevert(
            abi.encodeWithSelector(
                BridgeReceiver.AlreadyProcessed.selector,
                _msgId(0)
            )
        );
        epB.deliverNext(0);
    }

    function test_untrusted_source_reverts() public {
        // 把 trusted 关掉
        receiverB.setTrusted(CHAIN_A, address(senderA), false);

        senderA.bridge(CHAIN_B, address(receiverB), user, 100);

        vm.expectRevert(
            abi.encodeWithSelector(
                BridgeReceiver.UntrustedSource.selector,
                CHAIN_A,
                address(senderA)
            )
        );
        epB.deliverNext(0);
    }

    // 演示：为了拿 messageId，你可以在 MockLZEndpoint 里补一个 view：
    function _msgId(uint256 idx) internal view returns (bytes32) {
        // 如果你没写 getter，就先按同样规则重算：
        // 需要 srcApp=senderA, nonce=1, payload=abi.encode(user,100)
        bytes memory payload = abi.encode(user, uint256(100));
        return
            keccak256(
                abi.encode(CHAIN_A, address(senderA), uint64(1), payload)
            );
    }
}
