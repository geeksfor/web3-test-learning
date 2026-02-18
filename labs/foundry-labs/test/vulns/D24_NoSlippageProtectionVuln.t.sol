// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D24_SimpleERC20.sol";
import "../../src/vulns/D24_SimpleAMM.sol";

contract D24_NoSlippageProtection_Vuln_Test is Test {
    SimpleERC20 tokenA;
    SimpleERC20 tokenB;
    SimpleAMM amm;

    address lp = address(0x1); /// 是资金池受益者，投钱的
    address alice = address(0xA11CE);
    address attacker = address(0xBAD);

    function setUp() public {
        tokenA = new SimpleERC20("TokenA", "A");
        tokenB = new SimpleERC20("TokenB", "B");
        amm = new SimpleAMM(tokenA, tokenB);

        // mint
        tokenA.mint(lp, 2000 ether);
        tokenB.mint(lp, 2000 ether);

        tokenA.mint(alice, 100 ether);
        tokenB.mint(alice, 0);

        tokenA.mint(attacker, 1000 ether);
        tokenB.mint(attacker, 1000 ether);

        // LP provide 1000A:1000B
        vm.startPrank(lp);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1000 ether, 1000 ether);
        vm.stopPrank();

        // approvals
        vm.prank(alice);
        tokenA.approve(address(amm), type(uint256).max);

        vm.startPrank(attacker);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function test_vuln_anyPriceExecutes_whenNoMinOut() public {
        uint256 amountInAlice = 10 ether;

        // 1) 正常情况下 Alice 预期能拿到多少 B
        uint256 expectedNormal = amm.getAmountOut(
            amountInAlice,
            amm.reserve0(),
            amm.reserve1()
        );

        // 2) attacker 先 A->B 大额 swap，把价格打歪（让 B 变贵，Alice 换到更少 B）
        vm.prank(attacker);
        amm.swapExactIn_NoMinOut(address(tokenA), 500 ether);

        // 3) Alice 用漏洞 swap：没有 minOut，应该仍然成交
        uint256 balBefore = tokenB.balanceOf(alice);
        vm.prank(alice);
        uint256 outAfter = amm.swapExactIn_NoMinOut(
            address(tokenA),
            amountInAlice
        );
        uint256 balAfter = tokenB.balanceOf(alice);

        assertEq(balAfter - balBefore, outAfter);

        // 4) 关键断言：成交了，但价格极差（“任意价格都成交”）
        // 你可以用比例阈值来表达“不可接受”
        assertLt(outAfter, (expectedNormal * 70) / 100); // 比正常少 30% 以上

        // 便于观察
        emit log_named_uint("expectedNormal", expectedNormal);
        emit log_named_uint("outAfterSandwich", outAfter);
    }
}
