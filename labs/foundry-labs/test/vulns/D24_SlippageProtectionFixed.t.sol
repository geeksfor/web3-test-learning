// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D24_SimpleERC20.sol";
import "../../src/vulns/D24_SimpleAMM.sol";

contract D24_SlippageProtection_Fixed_Test is Test {
    SimpleERC20 tokenA;
    SimpleERC20 tokenB;
    SimpleAMM amm;

    address lp = address(0x1);
    address alice = address(0xA11CE);
    address attacker = address(0xBAD);

    function setUp() public {
        tokenA = new SimpleERC20("TokenA", "A");
        tokenB = new SimpleERC20("TokenB", "B");
        amm = new SimpleAMM(tokenA, tokenB);

        tokenA.mint(lp, 2000 ether);
        tokenB.mint(lp, 2000 ether);

        tokenA.mint(alice, 100 ether);
        tokenA.mint(attacker, 1000 ether);
        tokenB.mint(attacker, 1000 ether);

        vm.startPrank(lp);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1000 ether, 1000 ether);
        vm.stopPrank();

        vm.prank(alice);
        tokenA.approve(address(amm), type(uint256).max);

        vm.startPrank(attacker);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function test_fix_reverts_whenOutBelowMinOut() public {
        uint256 amountInAlice = 10 ether;

        // 正常预期
        uint256 expectedNormal = amm.getAmountOut(
            amountInAlice,
            amm.reserve0(),
            amm.reserve1()
        );
        uint256 minOut = (expectedNormal * 99) / 100; // 允许 1% 滑点
        uint256 deadline = block.timestamp;

        // attacker 打歪价格
        vm.prank(attacker);
        amm.swapExactIn_NoMinOut(address(tokenA), 500 ether);

        // Alice 带 minOut：应该 revert
        vm.prank(alice);
        vm.expectRevert(); // 也可以写 encodeWithSelector 精确匹配
        amm.swapExactIn(address(tokenA), amountInAlice, minOut, deadline);
    }

    function test_fix_deadlineExpired_reverts() public {
        uint256 amountInAlice = 1 ether;
        uint256 expectedNormal = amm.getAmountOut(
            amountInAlice,
            amm.reserve0(),
            amm.reserve1()
        );

        vm.warp(100);
        vm.prank(alice);
        vm.expectRevert();
        amm.swapExactIn(address(tokenA), amountInAlice, expectedNormal, 99);
    }
}
