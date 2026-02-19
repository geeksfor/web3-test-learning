// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D26_TimestampWindowVuln.sol";
import "../../src/vulns/D26_TimestampWindowFixed.sol";

contract D26_TimestampWindow_Test is Test {
    address alice = address(0xA11CE);

    uint256 saleStart;
    uint256 saleEnd;

    D26_TimestampWindowVuln vuln;
    D26_TimestampWindowFixed fixedC;

    function setUp() public {
        // 给测试账户一些 ETH
        vm.deal(alice, 10 ether);

        saleStart = 1_000;
        saleEnd = 2_000;

        vuln = new D26_TimestampWindowVuln(saleStart, saleEnd);
        fixedC = new D26_TimestampWindowFixed(saleStart, saleEnd);
    }

    /// 1) 证明：同一笔“买入意图”，只差几秒，价格就从 1 ether 变成 0.1 ether
    /// 这就是“矿工可操控窗口”：出块者只要把 timestamp 往后/往前偏几秒，就能改变分支
    function test_vuln_minerCanFlipPrice_withSmallWarp() public {
        // t = saleEnd - 11：不在最后10秒内 => FULL_PRICE
        vm.warp(saleEnd - 11);
        vm.prank(alice);
        vuln.buy{value: 1 ether}(); // ✅ 成功

        // t = saleEnd - 10：进入最后10秒 => DISCOUNT_PRICE
        vm.warp(saleEnd - 10);
        vm.prank(alice);
        vuln.buy{value: 0.1 ether}(); // ✅ 成功

        // 反过来：如果此时 alice 还按 FULL_PRICE 付，就会失败（分支被翻转）
        vm.warp(saleEnd - 10);
        vm.prank(alice);
        vm.expectRevert("wrong price");
        vuln.buy{value: 1 ether}();
    }

    /// 2) 边界条件测试：恰好等于 saleEnd - 10 时，被认为“打折”
    /// 审计视角：< vs <= / >= 的边界是否符合预期？会不会被卡边界套利？
    function test_vuln_boundary_isDiscountAtExactCutoff() public {
        vm.warp(saleEnd - 10);
        vm.prank(alice);
        vuln.buy{value: 0.1 ether}(); // 说明边界落在折扣侧
    }

    /// 3) 修复验证：Fixed 把折扣窗口变粗（例如 60 秒），避免“最后10秒”这种极窄窗口
    /// 这里我们证明：在最后 59 秒 / 61 秒的分界才切换，秒级微调（几秒）不再“价值巨大翻转”
    function test_fixed_reducesSecondLevelManipulation() public {
        // t = saleEnd - 61：还未进入最后 60 秒 => FULL_PRICE
        vm.warp(saleEnd - 61);
        vm.prank(alice);
        fixedC.buy{value: 1 ether}();

        // t = saleEnd - 59：进入最后 60 秒 => DISCOUNT_PRICE
        vm.warp(saleEnd - 59);
        vm.prank(alice);
        fixedC.buy{value: 0.1 ether}();

        // “小幅偏移 1~2 秒就翻转价值巨大” 的情况被弱化了：
        // 从 -11 到 -10 这种秒级切换不再发生（切换点变成 -60）
        vm.warp(saleEnd - 11);
        vm.prank(alice);
        fixedC.buy{value: 0.1 ether}(); // 在 fixed 里，-11 仍在最后60秒内 => 折扣价
    }
}
