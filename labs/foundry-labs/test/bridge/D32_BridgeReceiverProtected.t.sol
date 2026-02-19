// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/bridge/D32_BridgeReceiverProtected.sol";

// 一个最小可 mint 的 token（你也可以换成你项目里的 SimpleMintableERC20）
contract SimpleMintableERC20 is IMintable {
    string public name = "T";
    string public symbol = "T";
    uint8 public decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract BridgeReceiverProtectedTest is Test {
    BridgeReceiverProtected receiver;
    SimpleMintableERC20 token;

    address endpoint = address(0xE0F);
    address srcApp = address(0xA11CE);
    address to = address(0xB0B);

    uint32 srcChainId = 101; // 随便写个示例
    uint64 nonce = 1;

    function setUp() public {
        token = new SimpleMintableERC20();
        receiver = new BridgeReceiverProtected(
            endpoint,
            IMintable(address(token))
        );
    }

    function _payload(
        address _to,
        uint256 _amount
    ) internal pure returns (bytes memory) {
        return abi.encode(_to, _amount);
    }

    function _messageId(
        uint32 _srcChainId,
        address _srcApp,
        uint64 _nonce,
        bytes memory _payloadBytes
    ) internal pure returns (bytes32) {
        return
            keccak256(abi.encode(_srcChainId, _srcApp, _nonce, _payloadBytes));
    }

    function test_firstDelivery_mints_and_marksProcessed() public {
        uint256 amount = 100;
        bytes memory payload = _payload(to, amount);
        bytes32 messageId = _messageId(srcChainId, srcApp, nonce, payload);

        // only endpoint can call
        vm.prank(endpoint);
        receiver.lzReceive(srcChainId, srcApp, nonce, payload);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.totalSupply(), amount);
        assertTrue(receiver.processed(messageId));
    }

    function test_replay_sameMessage_reverts_and_stateUnchanged() public {
        uint256 amount = 100;
        bytes memory payload = _payload(to, amount);
        bytes32 messageId = _messageId(srcChainId, srcApp, nonce, payload);

        // 第一次：成功
        vm.prank(endpoint);
        receiver.lzReceive(srcChainId, srcApp, nonce, payload);

        uint256 balBefore = token.balanceOf(to);
        uint256 supplyBefore = token.totalSupply();

        // 第二次：重放 -> revert，并且状态不变
        vm.prank(endpoint);
        vm.expectRevert(
            abi.encodeWithSelector(
                BridgeReceiverProtected.Replay.selector,
                messageId
            )
        );
        receiver.lzReceive(srcChainId, srcApp, nonce, payload);

        assertEq(token.balanceOf(to), balBefore);
        assertEq(token.totalSupply(), supplyBefore);
        assertTrue(receiver.processed(messageId)); // 仍然是 true
    }

    function test_samePayload_differentNonce_shouldPass() public {
        uint256 amount = 100;
        bytes memory payload = _payload(to, amount);

        vm.prank(endpoint);
        receiver.lzReceive(srcChainId, srcApp, 1, payload);

        vm.prank(endpoint);
        receiver.lzReceive(srcChainId, srcApp, 2, payload);

        // 两次不同 nonce 都会 mint
        assertEq(token.balanceOf(to), 200);
        assertEq(token.totalSupply(), 200);
    }

    function test_nonEndpointCaller_reverts() public {
        bytes memory payload = _payload(to, 100);
        vm.expectRevert(
            abi.encodeWithSelector(
                BridgeReceiverProtected.NotEndpoint.selector,
                address(this)
            )
        );
        receiver.lzReceive(srcChainId, srcApp, nonce, payload);
    }
}
