// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleERC20.sol";

contract SimpleERC20Test is Test {
    SimpleERC20 token;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new SimpleERC20();
        token.mint(alice, 100 ether);
    }

    function test_transfer_ok_prank() public {
        // 下一次调用 msg.sender 伪装成 alice
        vm.prank(alice);
        bool ok = token.transfer(bob, 40 ether);

        assertTrue(ok);
        assertEq(token.balanceOf(alice), 60 ether);
        assertEq(token.balanceOf(bob), 40 ether);
    }

    function test_prank_only_once() public {
        vm.prank(alice);
        token.transfer(bob, 1 ether);

        // 这里 msg.sender 不再是 alice 了，是测试合约地址（余额为 0）
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleERC20.InsufficientBalance.selector,
                address(this),
                0,
                1 ether
            )
        );
        token.transfer(bob, 1 ether);
    }

    function test_transfer_ok_startPrank() public {
        vm.startPrank(alice);
        token.transfer(bob, 10 ether);
        token.transfer(bob, 5 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 85 ether);
        assertEq(token.balanceOf(bob), 15 ether);
    }

    function test_transfer_revert_insufficient_balance_simple() public {
        vm.prank(alice);
        vm.expectRevert(); // 只要 revert 就算通过
        token.transfer(bob, 999 ether);
    }

    function test_transfer_revert_insufficient_balance_exact() public {
        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleERC20.InsufficientBalance.selector,
                alice,
                100 ether,
                101 ether
            )
        );
        token.transfer(bob, 101 ether);
    }
}
