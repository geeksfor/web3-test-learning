// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/fork/D52_SimpleLending.sol";

contract D52_CollateralBoundaryAndLiquidation_Test is Test {
    uint256 constant WAD = 1e18;

    address alice = address(0xA11CE);
    address liq = address(0xB0B);

    D52_TestERC20 collateral;
    D52_TestERC20 usd;
    D52_OracleMock oracle;
    D52_SimpleLending pool;

    function setUp() public {
        collateral = new D52_TestERC20("COL", "COL");
        usd = new D52_TestERC20("USD", "USD");
        oracle = new D52_OracleMock();

        // LTV 75%, LT 80%, closeFactor 50%, bonus 5%
        pool = new D52_SimpleLending(
            IERC20(address(collateral)),
            IERC20(address(usd)),
            oracle,
            0.75e18,
            0.80e18,
            0.50e18,
            0.05e18
        );

        // 价格：$2000 / COL
        oracle.setPrice(2000e18);

        // 给 alice 抵押品，给池子足够 usd 以便借出
        collateral.mint(alice, 10e18); // 10 COL
        usd.mint(address(pool), 1_000_000e18); // pool 有钱可借

        // 给清算人一些 usd 用于 repay
        usd.mint(liq, 1_000_000e18);

        vm.startPrank(alice);
        collateral.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liq);
        usd.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function test_boundary_borrow_exactly_max_ok() public {
        // alice 抵押 1 COL => 价值 $2000
        vm.startPrank(alice);
        pool.deposit(1e18);

        // max debt value = 2000 * 0.75 = 1500
        // debt token $1 => 可借 1500 USD
        pool.borrow(1500e18);
        vm.stopPrank();

        assertEq(pool.debtOf(alice), 1500e18);
        assertEq(usd.balanceOf(alice), 1500e18);
    }

    function test_boundary_borrow_max_plus_1_reverts() public {
        vm.startPrank(alice);
        pool.deposit(1e18);

        // 1500 + 1 wei (最小单位) => 应该超限
        vm.expectRevert();
        pool.borrow(1500e18 + 1);
        vm.stopPrank();
    }

    function test_liquidation_triggered_after_price_drop() public {
        // 初始：抵押 1 COL($2000)，借 1500（LTV=75%），仍健康
        vm.startPrank(alice);
        pool.deposit(1e18);
        pool.borrow(1500e18);
        vm.stopPrank();

        assertFalse(pool.isLiquidatable(alice));

        // 触发清算：需要 debt > collateralValue * LT
        // LT=80%，若 price 跌到 P：
        // collateralValue*0.8 = (1*P)*0.8
        // 要让 1500 > 0.8P => P < 1875
        oracle.setPrice(1874e18);

        assertTrue(pool.isLiquidatable(alice));
    }

    function test_liquidate_repays_and_seizes_collateral_with_bonus_and_closeFactor()
        public
    {
        // 建仓
        vm.startPrank(alice);
        pool.deposit(1e18);
        pool.borrow(1500e18);
        vm.stopPrank();

        // 跌价进入可清算
        oracle.setPrice(1800e18);
        assertTrue(pool.isLiquidatable(alice));

        uint256 aliceDebtBefore = pool.debtOf(alice);
        uint256 aliceColBefore = pool.collateralOf(alice);
        uint256 liqColBefore = collateral.balanceOf(liq);

        // closeFactor = 50% => 最多 repay 750
        vm.startPrank(liq);
        // 超过 closeFactor 应 revert
        vm.expectRevert();
        pool.liquidate(alice, 751e18);

        // 正常清算：repay 750
        pool.liquidate(alice, 750e18);
        vm.stopPrank();

        // 债务下降
        assertEq(pool.debtOf(alice), aliceDebtBefore - 750e18);

        // 清算人拿走抵押品（含 5% bonus）
        // seizeValue = 750 * (1+0.05) = 787.5 美元
        // price = 1800 => seizeAmount = 787.5/1800 = 0.4375 COL
        // 精确到 1e18：0.4375e18 = 437500000000000000
        uint256 expectedSeize = 437500000000000000;
        assertEq(collateral.balanceOf(liq) - liqColBefore, expectedSeize);
    }

    function test_liquidation_boundary_debt_equals_threshold_not_liquidatable()
        public
    {
        // 让 debt == collateralValue * LT 恰好等于阈值
        // 抵押 1 COL，price=2000 => collateralValue=2000
        // threshold = 2000*0.8=1600
        vm.startPrank(alice);
        pool.deposit(1e18);
        pool.borrow(1500e18);
        vm.stopPrank();

        // 把价格调到：threshold=1500 => P*0.8=1500 => P=1875
        oracle.setPrice(1875e18);

        // 我们的 isLiquidatable 使用 debtValue > threshold（严格大于）
        // debt=1500，threshold=1500 => 不可清算
        assertFalse(pool.isLiquidatable(alice));

        // 再跌 1 => 可清算（边界）
        oracle.setPrice(1874e18);
        assertTrue(pool.isLiquidatable(alice));
    }
}
