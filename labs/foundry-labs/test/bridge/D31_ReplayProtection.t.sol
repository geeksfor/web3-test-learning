// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/bridge/D31_SimpleMintableERC20.sol";
import "../../src/bridge/D31_BridgeReceiver.sol";

contract D31_ReplayProtection_Test is Test {
    SimpleMintableERC20 token;
    BridgeReceiver receiver;

    address endpoint = address(0xE11E01);
    address user = address(0xA11CE);
    address srcApp = address(0xBEEF);

    uint16 srcChainId = 101;
    uint64 nonce = 777;

    function setUp() public {
        token = new SimpleMintableERC20();
        receiver = new BridgeReceiver(endpoint, address(token));
    }

    function test_replay_same_message_reverts_and_state_unchanged() public {
        bytes memory payload = abi.encode(user, 100);

        // ---- 1) 第一次：成功执行 ----
        vm.prank(endpoint);
        receiver.receiveMessage(srcChainId, srcApp, nonce, payload);

        assertEq(token.balanceOf(user), 100);
        assertEq(token.totalSupply(), 100);

        // ---- 2) 第二次重放：必须 revert，并且状态不变 ----
        uint256 balBefore = token.balanceOf(user);
        uint256 supplyBefore = token.totalSupply();

        bytes32 messageId = receiver.computeMessageId(
            srcChainId,
            srcApp,
            nonce,
            payload
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                BridgeReceiver.AlreadyProcessed.selector,
                messageId
            )
        );
        vm.prank(endpoint);
        receiver.receiveMessage(srcChainId, srcApp, nonce, payload);

        // 状态不变
        assertEq(token.balanceOf(user), balBefore);
        assertEq(token.totalSupply(), supplyBefore);
    }
}
