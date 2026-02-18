// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D25_GasGriefVuln.sol";
import "../../src/vulns/D25_GasGriefFixed_Pagination.sol";

contract D25_GasGrief_Test is Test {
    D25_GasGriefVuln vuln;
    D25_GasGriefFixed_Pagination fixedC;

    address owner = address(this);

    function setUp() public {
        vuln = new D25_GasGriefVuln();
        fixedC = new D25_GasGriefFixed_Pagination();
    }

    /// -------------------------
    /// 1) 漏洞：小规模可用
    /// -------------------------
    function test_vuln_distribute_small_ok() public {
        // 注册少量参与者
        for (uint256 i = 0; i < 20; i++) {
            address p = makeAddr(string(abi.encodePacked("p", vm.toString(i))));
            vm.prank(p);
            vuln.register();
        }

        // 限制 gas 也能跑完（20 人还不大）
        vuln.distribute{gas: 500_000}(1);

        // 随便验一个
        address p0 = makeAddr("p0");
        assertEq(vuln.credits(p0), 1);
    }

    /// --------------------------------------------------------
    /// 2) 漏洞：达到阈值后必失败（固定 gas 下 OOG / revert）
    /// --------------------------------------------------------
    function test_vuln_distribute_hits_threshold_and_fails() public {
        uint256 gasCap = 500_000; // 模拟“区块/交易可用 gas 上限”
        uint256 amountEach = 1;

        // 我们逐步加人，直到在 gasCap 下 distribute 必失败
        // 为了让测试稳定：每次都尝试调用 distribute{gas: gasCap}
        // 一旦数组足够大，会因为循环太长导致 OutOfGas => revert
        bool failed = false;
        uint256 n = 0;

        while (!failed && n < 5_000) {
            // 增加一个参与者
            address p = makeAddr(
                string(abi.encodePacked("att", vm.toString(n)))
            );
            vm.prank(p);
            vuln.register();
            n++;

            // 每增加一些人就探测一次（避免太慢）
            if (n % 50 == 0) {
                // 期待：总会到一个点失败（OOG 会表现为 revert）
                // 注意：在 Foundry 中 OOG 通常可用 expectRevert 捕获
                vm.expectRevert();
                vuln.distribute{gas: gasCap}(amountEach);

                // 如果确实 revert 了，expectRevert 会吞掉，
                // 下面这行仍会执行 => 我们标记 failed = true 并 break
                failed = true;
            }
        }

        assertTrue(failed, "should eventually fail under fixed gas cap");
        emit log_named_uint("threshold participants (approx)", n);
    }

    /// --------------------------------------------------------
    /// 3) 修复：分页分发在固定 gas 下可持续推进
    /// --------------------------------------------------------
    function test_fixed_pagination_progresses_under_gas_cap() public {
        uint256 gasCap = 200_000;
        uint256 amountEach = 1;

        // 注册很多参与者（比 vuln 更大）
        for (uint256 i = 0; i < 1_000; i++) {
            address p = makeAddr(string(abi.encodePacked("p", vm.toString(i))));
            vm.prank(p);
            fixedC.register();
        }

        // 通过分批方式推进 cursor，永远不会因为单笔 O(n) 直接爆掉
        // 每次最多处理 30 个（你可以调大/调小）
        for (uint256 round = 0; round < 40; round++) {
            // 不需要 expectRevert：应该都能在 gasCap 下成功
            fixedC.distributeChunk{gas: gasCap}(amountEach, 5);
        }

        // 游标应该向前推进
        assertGt(fixedC.cursor(), 0);

        // 验证一部分人已经拿到 credits
        address p0 = makeAddr("p0");
        assertEq(fixedC.credits(p0), 1); // 第一次 chunk 里会覆盖到 p0
    }
}
