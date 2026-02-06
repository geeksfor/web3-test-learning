// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/OpenZeppelinSimple/OwnableBadMint.sol";

contract OwnableBadMintTest is Test {
    OwnableBadMint token;

    address alice = address(0xA11CE);
    address attacker = address(0xBEEF);

    function setUp() public {
        token = new OwnableBadMint(alice);
        // owner 默认是部署者（本测试合约）
    }

    function test_Bad_anyoneCanMint() public {
        uint256 amount = 100;

        // 攻击者可以 mint 给自己（越权成功）
        vm.prank(attacker);
        token.mint(attacker, amount);
        assertEq(token.balanceOf(attacker), amount);
        assertEq(token.totalSupply(), amount);
    }
}
