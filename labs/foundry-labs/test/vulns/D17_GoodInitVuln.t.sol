// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D17_GoodInit.sol";

contract D17_GoodInit_Test is Test {
    D17_GoodInit good;

    address alice = address(0xA11CE);
    address attacker = address(0xB0B);
    address aliceTreasury = address(0xAA01);
    address attackerTreasury = address(0xBB01);

    function setUp() public {
        // 直接部署实现合约（这里不建 Proxy，先验证 initializer 语义）
        good = new D17_GoodInit();
    }

    /// @notice ✅ 第一次 initialize 成功；第二次必须 revert（防重复初始化夺权）
    function test_initialize_onlyOnce() public {
        vm.prank(alice);
        good.initialize(alice, aliceTreasury);

        assertEq(good.owner(), alice);
        assertEq(good.treasury(), aliceTreasury);

        // attacker 试图二次 initialize -> 必须 revert
        vm.prank(attacker);
        vm.expectRevert(); // OZ 版本不同，revert selector 可能不同，这里用“任意 revert”即可
        good.initialize(attacker, attackerTreasury);

        // 状态未被覆盖
        assertEq(good.owner(), alice);
        assertEq(good.treasury(), aliceTreasury);
    }

    /// @notice ✅ onlyOwner 生效：未夺权情况下 attacker 不能 setTreasury / sweepETH
    function test_onlyOwner_protects_sensitive_functions() public {
        vm.prank(alice);
        good.initialize(alice, aliceTreasury);

        // attacker 不能 setTreasury
        vm.prank(attacker);
        vm.expectRevert("not owner");
        good.setTreasury(attackerTreasury);

        // attacker 不能 sweep
        vm.prank(attacker);
        vm.expectRevert("not owner");
        good.sweepETH();
    }

    /// @notice ✅ sweepETH 正常：owner 可把合约里的 ETH 转到 treasury
    function test_sweepETH_owner_can_sweep() public {
        vm.prank(alice);
        good.initialize(alice, aliceTreasury);

        // 给合约打 5 ETH
        vm.deal(address(this), 10 ether);
        (bool ok, ) = address(good).call{value: 5 ether}("");
        require(ok, "fund failed");
        assertEq(address(good).balance, 5 ether);

        uint256 before = aliceTreasury.balance;

        vm.prank(alice);
        good.sweepETH();

        assertEq(address(good).balance, 0);
        assertEq(aliceTreasury.balance, before + 5 ether);
    }

    /// @notice （可选加分）V2 初始化：reinitializer(2) 只能执行一次
    function test_initializeV2_onlyOnce() public {
        vm.prank(alice);
        good.initialize(alice, aliceTreasury);

        // 第一次 V2 初始化成功
        vm.prank(alice);
        good.initializeV2(300);
        assertEq(good.feeBps(), 300);

        // 第二次 V2 初始化必须 revert
        vm.prank(alice);
        vm.expectRevert();
        good.initializeV2(500);

        // 值不变
        assertEq(good.feeBps(), 300);
    }

    // 让本测试合约能接收 ETH（向 good 合约转账更方便）
    receive() external payable {}
}
