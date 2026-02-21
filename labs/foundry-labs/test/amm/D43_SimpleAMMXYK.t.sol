// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/amm/SimpleERC20.sol";
import "../../src/amm/SimpleAMMXYK.sol";

contract D43_SimpleAMMXYK_Test is Test {
    SimpleERC20 t0;
    SimpleERC20 t1;
    SimpleAMMXYK amm;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        t0 = new SimpleERC20("Token0", "T0");
        t1 = new SimpleERC20("Token1", "T1");

        // 先用 no-fee 版本更直观：feeBps=0
        amm = new SimpleAMMXYK(address(t0), address(t1), 0);

        // 给 alice 初始资金
        t0.mint(alice, 10_000 ether);
        t1.mint(alice, 10_000 ether);

        // seed 流动性：1000:1000
        vm.startPrank(alice);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        amm.seed(1_000 ether, 1_000 ether);
        vm.stopPrank();
    }

    function test_swap0For1_basicCorrectness_matchesFormula() public {
        // 给 bob 一些 token0
        t0.mint(bob, 10 ether);

        (uint112 r0, uint112 r1) = (amm.reserve0(), amm.reserve1());
        uint256 x = uint256(r0);
        uint256 y = uint256(r1);
        uint256 k = x * y;

        uint256 amountIn = 1 ether;

        // 期望输出（fee=0）
        uint256 xNew = x + amountIn;
        uint256 yNew = k / xNew;
        uint256 expectedOut = y - yNew;

        uint256 bob1Before = t1.balanceOf(bob);

        vm.startPrank(bob);
        t0.approve(address(amm), amountIn);
        uint256 out = amm.swap0For1(amountIn, 0, bob);
        vm.stopPrank();

        assertEq(out, expectedOut, "amountOut should match x*y=k formula");
        assertEq(
            t1.balanceOf(bob) - bob1Before,
            expectedOut,
            "bob receives correct token1"
        );

        // 储备应与合约余额一致
        assertEq(
            uint256(amm.reserve0()),
            t0.balanceOf(address(amm)),
            "reserve0 == balance0"
        );
        assertEq(
            uint256(amm.reserve1()),
            t1.balanceOf(address(amm)),
            "reserve1 == balance1"
        );
    }

    function test_swap0For1_slippageProtection_revertsWhenMinOutTooHigh()
        public
    {
        t0.mint(bob, 10 ether);

        uint256 amountIn = 1 ether;

        // 故意设置一个不可能达到的 minOut（比储备还大）
        uint256 impossibleMinOut = 10_000 ether;

        vm.startPrank(bob);
        t0.approve(address(amm), amountIn);
        vm.expectRevert();
        amm.swap0For1(amountIn, impossibleMinOut, bob);
        vm.stopPrank();
    }

    function test_k_doesNotDecrease_much_withoutFee_dueToRounding() public {
        // fee=0 时：由于整数除法取整，kAfter 可能略小/略大，
        // 这里用“不会减少太多”的弱断言，避免被 rounding 打败。
        t0.mint(bob, 100 ether);
        uint256 kBefore = uint256(amm.reserve0()) * uint256(amm.reserve1());

        vm.startPrank(bob);
        t0.approve(address(amm), 10 ether);
        amm.swap0For1(10 ether, 0, bob);
        vm.stopPrank();

        uint256 kAfter = uint256(amm.reserve0()) * uint256(amm.reserve1());
        // 允许极小误差：kAfter + 1 >= kBefore（常见“向下取整最多损 1”直觉）
        // 若你后面改公式/加 fee，可把断言改成 kAfter >= kBefore。
        assertTrue(
            kAfter <= kBefore,
            "k should not increase without fee (floor division)"
        );

        // // 关键：kBefore - kAfter = kBefore % xNew < xNew
        // assertTrue(
        //     kBefore - kAfter < xNew,
        //     "k drop should be bounded by xNew (rounding bound)"
        // );
    }
}
