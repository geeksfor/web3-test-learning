// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/bridge/D30_SimpleMintBurnERC20.sol";
import "../../src/mocks/lz/MockLZEndpoint.sol";
import "../../src/bridge/D30_BurnMintBridge.sol";

contract D30_NormalCrossChain_BurnMint_Test is Test {
    uint16 constant CHAIN_A = 1;
    uint16 constant CHAIN_B = 2;

    MockLZEndpoint endpointA;
    MockLZEndpoint endpointB;

    SimpleMintBurnERC20 tokenA;
    SimpleMintBurnERC20 tokenB;

    BurnMintBridge bridgeA;
    BurnMintBridge bridgeB;

    address user = address(0xA11CE);

    function setUp() public {
        endpointA = new MockLZEndpoint(CHAIN_A);
        endpointB = new MockLZEndpoint(CHAIN_B);

        endpointA.setRemote(CHAIN_B, endpointB);
        endpointB.setRemote(CHAIN_A, endpointA);

        tokenA = new SimpleMintBurnERC20();
        tokenB = new SimpleMintBurnERC20();

        bridgeA = new BurnMintBridge(tokenA, endpointA);
        bridgeB = new BurnMintBridge(tokenB, endpointB);

        bridgeB.setTrusted(CHAIN_A, address(bridgeA), true);

        // 给 user 一些 src 链余额
        tokenA.mint(user, 100 ether);
        assertEq(tokenA.balanceOf(user), 100 ether);
        assertEq(tokenB.balanceOf(user), 0);
    }

    function test_normalCrossChain_burnOnA_mintOnB() public {
        uint256 amount = 10 ether;

        uint256 aBefore = tokenA.balanceOf(user);
        uint256 bBefore = tokenB.balanceOf(user);

        // user 在 A 链调用 bridgeA，目标是 B 链的 bridgeB
        vm.prank(user);
        bridgeA.bridge(CHAIN_B, address(bridgeB), user, amount);
        endpointB.deliverNext(0);

        // 断言：A 链 burn 生效
        assertEq(tokenA.balanceOf(user), aBefore - amount);

        // 断言：B 链 mint 生效（因为 endpoint 在 send 时已经 deliver 回调了）
        assertEq(tokenB.balanceOf(user), bBefore + amount);
    }
}
