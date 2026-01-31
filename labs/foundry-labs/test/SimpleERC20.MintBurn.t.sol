// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleERC20.sol";

contract SimpleERC20MintBurnTest is Test {
    SimpleERC20 token;

    // 常用测试地址
    address owner;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address spender = address(0xA22CE);

    // 常用数量（用 ether 只是单位习惯，代表 10^18）
    uint256 constant ONE = 1 ether;
    uint256 constant INIT_MINT = 100 ether;

    function setUp() public {
        owner = address(this);

        token = new SimpleERC20();
        // token.mintOnlyOwner(alice, INIT_MINT);
    }

    function test_ownerMint_success_updatesSupplyAndBalance_andEmitsTransfer()
        public
    {
        uint256 amount = 100 ether;

        uint256 supplyBefore = token.totalSupply();
        uint256 balBefore = token.balanceOf(alice);

        // 事件断言：from/to 通常是 indexed
        // expectEmit(checkTopic1, checkTopic2, checkTopic3, checkData)
        // Transfer(from, to, value):
        //   topic0 = keccak256("Transfer(address,address,uint256)")
        //   topic1 = indexed from
        //   topic2 = indexed to
        //   data   = value
        vm.expectEmit(true, true, false, true);
        emit SimpleERC20.Transfer(address(0), alice, amount);

        // owner 调用 mint（这里不需要 prank，因为 owner 就是 address(this)）
        token.mintOnlyOwner(alice, amount);
        // 1) totalSupply 增加
        assertEq(token.totalSupply(), supplyBefore + amount);

        // 2) balanceOf(alice) 增加
        assertEq(token.balanceOf(alice), balBefore + amount);
    }

    function test_burn_success_updatesSupplyAndBalance_andEmitsTransfer()
        public
    {
        uint256 mintAmount = 100 ether;
        uint256 burnAmount = 40 ether;

        // 1) owner mint 给 alice
        token.mintOnlyOwner(alice, mintAmount);

        uint256 supplyBefore = token.totalSupply();
        uint256 aliceBalBefore = token.balanceOf(alice);

        // 2) 期待事件：Transfer(alice, address(0), burnAmount)
        // 参数含义：checkTopic1(from), checkTopic2(to), checkTopic3(一般不用), checkData(value)
        vm.expectEmit(true, true, false, true, address(token));
        emit SimpleERC20.Transfer(alice, address(0), burnAmount);

        // 3) alice burn
        vm.prank(alice);
        token.burn(burnAmount);

        // 4) 断言：alice balance 减少 & totalSupply 减少
        assertEq(token.balanceOf(alice), aliceBalBefore - burnAmount);
        assertEq(token.totalSupply(), supplyBefore - burnAmount);
    }

    function test_burnFrom_success_reducesAllowance_andBurns() public {
        uint256 mintAmount = 100 ether;
        uint256 burnAmount = 40 ether;

        // 1) owner mint 给 alice
        token.mintOnlyOwner(alice, mintAmount);

        uint256 supplyBefore = token.totalSupply();
        uint256 aliceBalBefore = token.balanceOf(alice);

        // 2) approve spender 80 ether
        vm.prank(alice);
        token.approve(spender, 80 ether);

        assertEq(token.allowance(alice, spender), 80 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit SimpleERC20.Transfer(alice, address(0), burnAmount);
        vm.prank(spender);
        token.burnFrom(alice, burnAmount);

        assertEq(token.allowance(alice, spender), 80 ether - burnAmount);
        assertEq(token.balanceOf(alice), aliceBalBefore - burnAmount);
        assertEq(token.totalSupply(), supplyBefore - burnAmount);
    }

    // 非 owner mint
    function test_mint_revert_whenNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(SimpleERC20.Unauthorized.selector, alice)
        );
        token.mintOnlyOwner(alice, 10 ether);
    }

    // mint 到 zero 地址
    function test_mint_revert_whenToZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(SimpleERC20.InvalidAddress.selector)
        );
        token.mintOnlyOwner(address(0), 10 ether);
    }

    // burn 余额不足
    function test_burn_revert_whenInsufficientBalance() public {
        uint256 amount = 100 ether;
        uint256 bal = 0 ether;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleERC20.InsufficientBalance.selector,
                alice,
                bal,
                amount
            )
        );
        token.burn(amount);
    }

    // burnFrom allowance 不足
    function test_burnFrom_revert_whenInsufficientAllowance() public {
        token.mintOnlyOwner(alice, 100 ether);
        vm.prank(alice);
        token.approve(spender, 10 ether);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleERC20.InsufficientAllowance.selector,
                spender,
                10 ether,
                80 ether
            )
        );
        token.burnFrom(alice, 80 ether);
    }
}
