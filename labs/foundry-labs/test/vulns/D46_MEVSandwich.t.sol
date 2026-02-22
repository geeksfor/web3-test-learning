// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D46_MEVSandwich.sol";

contract D46_MEVSandwich_Test is Test {
    SimpleERC20 tokenA;
    SimpleERC20 tokenB;
    SimpleAMMXYK_D46 amm;

    address lp = makeAddr("lp");
    address victim = makeAddr("victim");
    address attacker = makeAddr("attacker");

    function setUp() public {
        tokenA = new SimpleERC20("TokenA", "A");
        tokenB = new SimpleERC20("TokenB", "B");
        amm = new SimpleAMMXYK_D46(tokenA, tokenB);

        // 给 LP 初始资金并建池
        tokenA.mint(lp, 2000 ether);
        tokenB.mint(lp, 2000 ether);

        vm.startPrank(lp);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        amm.init(1000 ether, 1000 ether);
        vm.stopPrank();

        // 给 victim 和 attacker 资金
        tokenA.mint(victim, 100 ether);
        tokenA.mint(attacker, 1000 ether); // 攻击者需要更大额度做 front-run
        tokenB.mint(attacker, 0); // 初始没有 B 也没关系

        vm.prank(victim);
        tokenA.approve(address(amm), type(uint256).max);

        vm.prank(attacker);
        tokenA.approve(address(amm), type(uint256).max);

        vm.prank(attacker);
        tokenB.approve(address(amm), type(uint256).max);
    }

    /// @notice D46 核心：证明 victim 在夹子下实际成交变差
    function test_sandwich_victim_fill_gets_worse() public {
        uint256 victimIn = 10 ether;

        // -------- baseline：无夹子时 victim 能拿到多少 B --------
        uint256 outBase = amm.quoteOutAtoB(victimIn);

        // 让 victim 真换一次（用 vuln 版）以确认与 quote 一致（可选）
        vm.startPrank(victim);
        uint256 victimB_before = tokenB.balanceOf(victim);
        amm.swapExactInVuln_AtoB(victimIn);
        uint256 outBaseReal = tokenB.balanceOf(victim) - victimB_before;
        vm.stopPrank();

        assertEq(outBaseReal, outBase, "baseline out should match quote");

        // 为了对比公平：重置状态（重新部署一套池）
        setUp();

        // -------- sandwich：attacker front-run -> victim -> attacker back-run --------
        uint256 attackerA_before = tokenA.balanceOf(attacker);

        // 1) attacker front-run：先大额 A->B 推坏价格
        vm.startPrank(attacker);
        uint256 frontIn = 200 ether;
        uint256 attackerB_before = tokenB.balanceOf(attacker);
        amm.swapExactInVuln_AtoB(frontIn);
        uint256 attackerB_got = tokenB.balanceOf(attacker) - attackerB_before;
        vm.stopPrank();

        // 2) victim 再换：同样 10 A，但会拿到更少 B
        uint256 outSandwichQuote = amm.quoteOutAtoB(victimIn);

        vm.startPrank(victim);
        uint256 victimB_before2 = tokenB.balanceOf(victim);
        amm.swapExactInVuln_AtoB(victimIn);
        uint256 outSandwichReal = tokenB.balanceOf(victim) - victimB_before2;
        vm.stopPrank();

        assertEq(
            outSandwichReal,
            outSandwichQuote,
            "sandwich out should match quote"
        );

        assertTrue(
            outSandwichReal < outBase,
            "victim fill should be worse under sandwich"
        );

        // 3) attacker back-run：把 B->A 换回去，吃回价格并获利
        // 3) attacker back-run：把 B->A 换回去，吃回价格并获利
        vm.startPrank(attacker);
        amm.swapExactIn_BtoA(attackerB_got);
        uint256 attackerA_after = tokenA.balanceOf(attacker);
        vm.stopPrank();

        assertTrue(
            attackerA_after > attackerA_before,
            "attacker should profit in simplified sandwich"
        );
    }

    /// @notice 修复：victim 带 minOut + deadline，夹子下应因滑点而 revert
    function test_fixed_minOut_reverts_under_sandwich() public {
        uint256 victimIn = 10 ether;

        // 先算「无夹子」基线输出，作为 victim 期望值
        uint256 outBase = amm.quoteOutAtoB(victimIn);
        uint256 minOut = (outBase * 99) / 100; // 允许 1% 滑点（示例）

        // attacker front-run 推坏价格
        vm.startPrank(attacker);
        amm.swapExactInVuln_AtoB(200 ether);
        vm.stopPrank();

        // victim 现在如果仍坚持 minOut（基于正常市场预期），就会因滑点过大失败
        vm.startPrank(victim);
        vm.expectRevert();
        amm.swapExactIn_AtoB(victimIn, minOut, block.timestamp + 60);
        vm.stopPrank();
    }

    /// @notice 修复：deadline 过期应 revert（防止交易在 mempool 长时间暴露更易被夹）
    function test_fixed_deadline_expired_reverts() public {
        vm.startPrank(victim);
        vm.expectRevert();
        amm.swapExactIn_AtoB(1 ether, 0, block.timestamp - 1);
        vm.stopPrank();
    }
}
