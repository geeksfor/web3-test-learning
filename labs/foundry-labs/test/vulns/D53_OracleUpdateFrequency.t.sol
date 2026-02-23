// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/fork/D53_OracleUpdate.sol";

contract D53_OracleUpdateFrequency_Test is Test {
    uint256 constant WAD = 1e18;

    address alice = makeAddr("alice");

    MockOracle oracle;
    SimpleLending lending;

    function setUp() public {
        oracle = new MockOracle();

        // liqThreshold=80%，maxOracleDelay=1小时（你也可以调更短，专门测“过期”）
        lending = new SimpleLending(oracle, 0.8e18, 3600);

        // 初始化喂一个高价：ETH=2000
        oracle.update(2000e18);

        // Alice 抵押 1 ETH
        vm.prank(alice);
        lending.depositCollateral(1e18);

        // Alice 借 1200 USD（在2000价下：抵押价值=2000，打8折=1600 > 1200，安全）
        vm.prank(alice);
        lending.borrow(1200e18);
    }

    function test_update_before_after_liquidation_condition_changes() public {
        // 1) 更新前：应当不触发清算
        bool liq0 = lending.isLiquidatable(alice);
        assertEq(liq0, false, "before update: should NOT be liquidatable");

        // 2) 时间过去一会儿，但 oracle 不更新：清算状态不会改变（因为价格还是旧的）
        vm.warp(block.timestamp + 300); // 5分钟
        bool liq1 = lending.isLiquidatable(alice);
        assertEq(liq1, false, "no update: still NOT liquidatable");

        // 3) Oracle 喂价跳变：ETH 从 2000 -> 1300
        // 抵押价值=1300，打8折=1040 < 1200 => 立刻可清算
        oracle.update(1300e18);

        bool liq2 = lending.isLiquidatable(alice);
        assertEq(liq2, true, "after update: should become liquidatable");

        // 4) 再来一次跳回去：ETH 从 1300 -> 2200
        // 抵押价值=2200，打8折=1760 > 1200 => 不该清算
        oracle.update(2200e18);

        bool liq3 = lending.isLiquidatable(alice);
        assertEq(liq3, false, "after rebound: should NOT be liquidatable");
    }

    function test_stale_price_reverts_and_blocks_liquidation_check() public {
        // 让时间直接超过 maxOracleDelay=3600
        vm.warp(block.timestamp + 3601);

        vm.expectRevert();
        lending.isLiquidatable(alice);
    }
}
