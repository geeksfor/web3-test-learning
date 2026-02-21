// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {SimpleERC20} from "../../src/mocks/SimpleERC20.sol";
import {D44_SlippageWithMinOut} from "../../src/vulns/D44_SlippageWithMinOut.sol";

contract D44_SlippageWithMinOut_Test is Test {
    SimpleERC20 t0;
    SimpleERC20 t1;
    D44_SlippageWithMinOut amm;

    address lp = makeAddr("lp");
    address alice = makeAddr("alice");
    address attacker = makeAddr("attacker");

    function setUp() public {
        t0 = new SimpleERC20("T0", "T0");
        t1 = new SimpleERC20("T1", "T1");
        amm = new D44_SlippageWithMinOut(t0, t1);

        t0.mint(lp, 10_000 ether);
        t1.mint(lp, 10_000 ether);

        t0.mint(alice, 1_000 ether);
        t1.mint(alice, 1_000 ether);

        t0.mint(attacker, 10_000 ether);
        t1.mint(attacker, 10_000 ether);

        vm.startPrank(lp);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1_000 ether, 1_000 ether);
        vm.stopPrank();

        vm.prank(alice);
        t0.approve(address(amm), type(uint256).max);

        vm.prank(attacker);
        t0.approve(address(amm), type(uint256).max);
        vm.prank(attacker);
        t1.approve(address(amm), type(uint256).max);
    }

    function test_fixed_minOut_blocks_sandwich_reverts() public {
        uint256 amountInAlice = 10 ether;

        // Alice 基于“当时报价”设置 minOut（容忍 1%）
        uint256 quotedOut = amm.quoteOut(address(t0), amountInAlice);
        uint256 minOut = (quotedOut * 99) / 100;

        // attacker 插队，改变价格
        vm.prank(attacker);
        // attacker 也得用 minOut+deadline，这里给 0 容忍即可（只为改价）
        amm.swapExactIn(
            address(t0),
            500 ether,
            0,
            block.timestamp + 1,
            attacker
        );

        // Alice 交易应当因为 Slippage 而 revert
        vm.prank(alice);
        vm.expectRevert();
        amm.swapExactIn(
            address(t0),
            amountInAlice,
            minOut,
            block.timestamp + 1,
            alice
        );
    }
}
