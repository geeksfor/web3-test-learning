// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Counter.sol";

contract CounterTest is Test {
    Counter counter;

    function setUp() public {
        counter = new Counter(42);
    }

    function test_DeployAndInitValue() public view {
        // 部署后 number 应该等于 42
        assertEq(counter.number(), 42);
    }

    function test_SetNumber() public {
        counter.setNumber(100);
        assertEq(counter.number(), 100);
    }

    function test_Increment() public {
        counter.increment();
        assertEq(counter.number(), 43);
    }
}
