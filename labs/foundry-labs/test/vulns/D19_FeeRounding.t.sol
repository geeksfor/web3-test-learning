// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/FeeCollectorBad.sol";

contract D19_FeeRoundingTest is Test {
    FeeCollectorBad fee;

    function setUp() public {
        fee = new FeeCollectorBad(30); // 0.30%
    }

    function test_fee_rounding_split_beats_single() public {
        uint256 parts = 1000;
        uint256 each = 333; // 确保 fee(each)=0 (333*30/10000=0)
        uint256 amount = parts * each; // 333000

        (, uint256 feeSingle) = fee.takeFee(amount);

        uint256 feeSplit;
        for (uint256 i = 0; i < parts; i++) {
            (, uint256 f) = fee.takeFee(each);
            feeSplit += f;
        }

        assertEq(feeSplit, 0);
        assertGt(feeSingle, 0);
        assertLt(
            feeSplit,
            feeSingle,
            "split should reduce fee in bad rounding"
        );
    }

    function test_fee_boundaries_small_amounts() public {
        // 找到使 fee=0 的小额区间（典型边界测试）
        for (uint256 amt = 1; amt < 10_000; amt++) {
            (, uint256 f) = fee.takeFee(amt);
            if (f == 0) {
                // 记录一个样例即可
                assertEq(f, 0);
                return;
            }
        }
        fail("expected to find zero-fee small amount");
    }

    function test_fee_large_amount() public {
        (, uint256 f) = fee.takeFee(1_000_000 ether);
        assertGt(f, 0);
    }
}
