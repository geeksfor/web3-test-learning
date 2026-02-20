// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {BridgeReceiver} from "../../src/bridge/D33_BridgeReceiver.sol";
import {IMintable} from "../../src/bridge/D33_BridgeReceiver.sol";
import {MessageIdLib} from "../../src/bridge/MessageIdLib.sol";

/// 非常简单的合约，用来验证使用
contract SimpleMintableERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

contract D33_DomainSeparation_Replay_Test is Test {
    using MessageIdLib for uint16;

    SimpleMintableERC20 token;
    BridgeReceiver receiver;

    uint16 constant DST_CHAIN = 101;
    address alice = address(0xA11CE);

    function setUp() public {
        token = new SimpleMintableERC20();
        receiver = new BridgeReceiver(DST_CHAIN, IMintable(address(token)));
    }

    function _payload(
        address to,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encode(to, amount);
    }

    // ✅ 1) 核心断言：messageId 必须包含 srcApp/dstApp/chainId → 任意改变都应变化
    function test_messageId_must_include_srcApp_dstApp_chainId() public view {
        uint16 srcChainId = 100;
        address srcAppA = address(0xAAA1);
        address srcAppB = address(0xAAA2);
        uint64 nonce = 1;
        bytes memory payload = _payload(alice, 100);

        bytes32 idA = MessageIdLib.compute(
            srcChainId,
            srcAppA,
            DST_CHAIN,
            address(receiver),
            nonce,
            payload
        );

        // 改 srcApp → 必须变化
        bytes32 idSrcAppChanged = MessageIdLib.compute(
            srcChainId,
            srcAppB,
            DST_CHAIN,
            address(receiver),
            nonce,
            payload
        );
        assertTrue(idA != idSrcAppChanged);

        // 改 dstApp → 必须变化
        bytes32 idDstAppChanged = MessageIdLib.compute(
            srcChainId,
            srcAppA,
            DST_CHAIN,
            address(0xBEEF),
            nonce,
            payload
        );
        assertTrue(idA != idDstAppChanged);

        // 改 chainId（src 或 dst 任意一侧）→ 必须变化
        bytes32 idSrcChainChanged = MessageIdLib.compute(
            uint16(999),
            srcAppA,
            DST_CHAIN,
            address(receiver),
            nonce,
            payload
        );
        assertTrue(idA != idSrcChainChanged);

        bytes32 idDstChainChanged = MessageIdLib.compute(
            srcChainId,
            srcAppA,
            uint16(202),
            address(receiver),
            nonce,
            payload
        );
        assertTrue(idA != idDstChainChanged);
    }

    // ✅ 2) 同域重放：同 srcChain/srcApp/dstApp/nonce/payload → 第二次必须 revert
    function test_replay_same_domain_reverts() public {
        uint16 srcChainId = 100;
        address srcApp = address(0xAAA1);
        uint64 nonce = 7;
        bytes memory payload = _payload(alice, 123);

        receiver.lzReceive(srcChainId, srcApp, nonce, payload);
        assertEq(token.balanceOf(alice), 123);

        // 第二次同样消息 = 重放
        bytes32 mid = MessageIdLib.compute(
            srcChainId,
            srcApp,
            DST_CHAIN,
            address(receiver),
            nonce,
            payload
        );
        vm.expectRevert(
            abi.encodeWithSelector(BridgeReceiver.Replay.selector, mid)
        );
        receiver.lzReceive(srcChainId, srcApp, nonce, payload);

        // 状态不应变化
        assertEq(token.balanceOf(alice), 123);
    }

    // ✅ 3) 跨 app 域隔离：srcApp 不同 → 不应互相影响（不应误判 replay）
    function test_crossApp_domainIsolation_not_mark_replay() public {
        uint16 srcChainId = 100;
        address srcAppA = address(0xAAA1);
        address srcAppB = address(0xAAA2);

        uint64 nonce = 1;
        bytes memory payload = _payload(alice, 10);

        receiver.lzReceive(srcChainId, srcAppA, nonce, payload);
        assertEq(token.balanceOf(alice), 10);

        // 同 nonce + 同 payload，但 srcApp 不同：应当被视为“不同域消息”，可以正常处理
        receiver.lzReceive(srcChainId, srcAppB, nonce, payload);
        assertEq(token.balanceOf(alice), 20);
    }

    // ✅ 4) 跨链域隔离：srcChainId 不同 → 不应互相影响
    function test_crossChain_domainIsolation_not_mark_replay() public {
        address srcApp = address(0xAAA1);
        uint64 nonce = 1;
        bytes memory payload = _payload(alice, 10);

        receiver.lzReceive(uint16(100), srcApp, nonce, payload);
        receiver.lzReceive(uint16(200), srcApp, nonce, payload);

        assertEq(token.balanceOf(alice), 20);
    }
}
