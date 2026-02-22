// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {IERC20View} from "./IERC20View.sol";

contract D51_UniswapV2_Readonly_Test is Test {
    // Uniswap V2: USDC/WETH Pair (mainnet)
    address constant PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    function setUp() public {
        // fork mainnet at latest
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
    }

    function test_readonly_invariants_uniswapV2Pair() public view {
        IUniswapV2Pair pair = IUniswapV2Pair(PAIR);

        // --- 基础地址不变量 ---
        address token0 = pair.token0();
        address token1 = pair.token1();

        assertTrue(token0 != address(0), "token0 is zero");
        assertTrue(token1 != address(0), "token1 is zero");
        assertTrue(token0 != token1, "token0 == token1");

        // --- reserves 不变量 ---
        (uint112 r0, uint112 r1, uint32 tsLast) = pair.getReserves();
        assertTrue(r0 > 0 && r1 > 0, "empty reserves");

        // tsLast 是 last update 的时间戳（不要求等于 block.timestamp）
        assertTrue(tsLast > 0, "timestampLast should exist");

        // --- 常量乘积核心量 ---
        // 注意：这里不要求 k “不变”，因为交易会改变 reserves，但 k 必须 > 0
        uint256 k = uint256(r0) * uint256(r1);
        assertTrue(k > 0, "k must be > 0");

        // --- totalSupply 不变量 ---
        uint256 supply = pair.totalSupply();
        assertTrue(supply > 0, "LP totalSupply is zero");

        // --- MINIMUM_LIQUIDITY 锁定（只读强校验点） ---
        // UniswapV2Pair: 首次铸造会把 1000 LP 锁到 address(0)
        uint256 burned = pair.balanceOf(address(0));
        assertTrue(burned >= 1000, "minimum liquidity not locked");

        // --- reserves 与实际 ERC20 余额的关系（审计常用健康检查） ---
        // 正常情况下：balance >= reserve（可能有人直接 transfer 进来导致 balance > reserve）
        // 但如果 balance < reserve 往往意味着状态异常（理论上 sync 会修正，但这里做健康断言）
        uint256 bal0 = IERC20View(token0).balanceOf(PAIR);
        uint256 bal1 = IERC20View(token1).balanceOf(PAIR);

        assertTrue(bal0 >= uint256(r0), "token0 balance < reserve0");
        assertTrue(bal1 >= uint256(r1), "token1 balance < reserve1");

        // --- 可选：读取一些“观测字段”不作强断言，只做 sanity check ---
        // 累计价格通常是非 0（成熟池），但严格来说可能为 0（新池/极端情况）
        // 这里我们只做“类型/可读性”的演示：不强依赖它一定非 0
        pair.price0CumulativeLast();
        pair.price1CumulativeLast();

        // fees on 时 kLast 可能非 0；fees off 时可能为 0
        pair.kLast();
    }

    function test_readonly_print_basic_info() public {
        IUniswapV2Pair pair = IUniswapV2Pair(PAIR);
        address token0 = pair.token0();
        address token1 = pair.token1();
        (uint112 r0, uint112 r1, ) = pair.getReserves();

        // 仅演示：把关键字段打印出来，方便你本地观察
        emit log_named_address("PAIR", PAIR);
        emit log_named_address("token0", token0);
        emit log_named_address("token1", token1);
        emit log_named_uint("reserve0", r0);
        emit log_named_uint("reserve1", r1);

        // token 元信息（symbol/decimals）只是辅助输出
        // 有些 token 可能没实现 symbol/decimals（老 token），这里 USDC/WETH 没问题
        emit log_named_string("symbol0", IERC20View(token0).symbol());
        emit log_named_string("symbol1", IERC20View(token1).symbol());
        emit log_named_uint("decimals0", IERC20View(token0).decimals());
        emit log_named_uint("decimals1", IERC20View(token1).decimals());
    }
}
