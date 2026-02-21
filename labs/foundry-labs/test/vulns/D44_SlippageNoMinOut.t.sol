// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {SimpleERC20} from "../../src/mocks/SimpleERC20.sol";
import {D44_SlippageNoMinOut} from "../../src/vulns/D44_SlippageNoMinOut.sol";

contract D44_SlippageNoMinOut_Test is Test {
    SimpleERC20 t0;
    SimpleERC20 t1;
    D44_SlippageNoMinOut amm;

    address lp = makeAddr("lp");
    address alice = makeAddr("alice");
    address attacker = makeAddr("attacker");

    function setUp() public {
        t0 = new SimpleERC20("T0", "T0");
        t1 = new SimpleERC20("T1", "T1");
        amm = new D44_SlippageNoMinOut(t0, t1);

        // 铸币
        t0.mint(lp, 10_000 ether);
        t1.mint(lp, 10_000 ether);

        t0.mint(alice, 1_000 ether);
        t1.mint(alice, 1_000 ether);

        t0.mint(attacker, 10_000 ether);
        t1.mint(attacker, 10_000 ether);

        // LP 加流动性 1000:1000
        vm.startPrank(lp);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1_000 ether, 1_000 ether);
        vm.stopPrank();

        // 预授权
        vm.prank(alice);
        t0.approve(address(amm), type(uint256).max);

        vm.prank(attacker);
        t0.approve(address(amm), type(uint256).max);
        vm.prank(attacker);
        t1.approve(address(amm), type(uint256).max);
    }

    /// 失败用例：Alice 看到的报价是基于“当时 reserve”
    /// 但 attacker 先交易改变 reserve，Alice 最终成交变差，且没有 minOut 保护 => 仍然成交
    function test_vuln_noMinOut_userGetsWorsePrice_butStillExecutes_FAILING()
        public
    {
        uint256 amountInAlice = 10 ether;

        // Alice 下单前看到的预期输出（报价）
        uint256 quotedOut = amm.quoteOut(address(t0), amountInAlice);

        // attacker 先用大单把价格打歪（模拟夹子前腿/插队）
        vm.prank(attacker);
        amm.swapExactIn(address(t0), 500 ether, attacker);

        // Alice 再 swap（因为没有 minOut，她不会 revert）
        uint256 balBefore = t1.balanceOf(alice);
        vm.prank(alice);
        uint256 outActual = amm.swapExactIn(address(t0), amountInAlice, alice);
        uint256 balAfter = t1.balanceOf(alice);

        assertEq(balAfter - balBefore, outActual);

        // 这里我们故意写“安全预期”：至少拿到报价的 99%（1% 滑点容忍）
        // 但因为 attacker 插队，Alice 实际拿到的会显著更少 => 断言失败（红测）
        uint256 minAcceptable = (quotedOut * 99) / 100;

        // ❌ 失败点：没有 minOut 时，合约不会帮你挡住差价
        assertLe(
            outActual,
            minAcceptable,
            "should have been protected by minOut, but it was not"
        );
    }
}
