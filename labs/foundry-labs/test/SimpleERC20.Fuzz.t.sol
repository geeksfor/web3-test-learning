// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleERC20.sol";

/*
alice（token owner）
bob（spender）
carol（receiver）
*/

contract SimpleERC20FuzzTest is Test {
    SimpleERC20 token;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCcc1);

    uint256 constant INIT = 100 ether;

    function setUp() public {
        token = new SimpleERC20();
        token.mint(alice, INIT);
    }

    function testFuzz_transfer_balanceConservation(uint256 amount) public {
        // 1) 限制 amount：1..INIT（确保不会 revert）
        amount = bound(amount, 1, INIT);

        // 2) 记录转账前状态
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);
        uint256 total = token.totalSupply();

        // 执行：模拟 alice 调用 transfer 给 bob
        vm.prank(alice);
        token.transfer(bob, amount);

        // 4) 断言：两人余额和守恒、totalSupply 不变、各自变化正确
        uint256 aliceCurrent = token.balanceOf(alice);
        uint256 bobCurrent = token.balanceOf(bob);
        uint256 totalCurrent = token.totalSupply();

        assertEq(aliceCurrent, aliceBefore - amount);
        assertEq(bobCurrent, bobBefore + amount);
        assertEq(aliceBefore + bobBefore, aliceCurrent + bobCurrent);
        assertEq(total, totalCurrent);
    }
}
