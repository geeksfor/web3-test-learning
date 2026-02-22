// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

// 最小 ERC20 接口（只用到 balanceOf/transfer）
interface IERC20 {
    function balanceOf(address) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
}

contract D50_Fork_Test is Test {
    // Ethereum mainnet USDC (Circle) address
    // 注意：这是 mainnet 上真实地址
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // 选一个“历史区块号”，固定住测试环境（示例：17,000,000）
    // 你也可以换成你想复现某事件的区块
    uint256 constant FORK_BLOCK = 24446296;

    // 选一个在该区块附近“持有大量 USDC 的地址”
    // 这类地址很多；如果这个地址在你选的区块余额不足，换一个即可
    address constant USDC_WHALE = 0xe1940f578743367F38D3f25c2D2d32D6636929B6; // 常见示例地址（不保证所有区块都有大量余额）

    address alice = makeAddr("alice");

    function setUp() public {
        // 从环境变量读取 RPC（你也可以用 vm.rpcUrl("mainnet")）
        string memory rpc = vm.envString("ETH_RPC_URL");

        // 关键：创建并选择 fork + 固定区块
        vm.createSelectFork(rpc, FORK_BLOCK);
    }

    function test_fork_readAndTransferUSDC() public {
        IERC20 usdc = IERC20(USDC);

        uint256 whaleBal = usdc.balanceOf(USDC_WHALE);
        emit log_named_uint("whale USDC balance", whaleBal);

        // 断言：这个地址在该区块确实有钱（否则就换地址或换区块）
        assertGt(
            whaleBal,
            1_000_000e6,
            "whale balance too small at this block"
        );

        // fork 环境里，你可以“扮演”任何地址发交易（用于测试）
        vm.prank(USDC_WHALE);
        bool ok = usdc.transfer(alice, 100e6); // 100 USDC (USDC decimals=6)
        assertTrue(ok, "transfer failed");

        assertEq(usdc.balanceOf(alice), 100e6, "alice should receive 100 USDC");
        assertEq(
            usdc.balanceOf(USDC_WHALE),
            whaleBal - 100e6,
            "whale balance should decrease"
        );
    }
}
