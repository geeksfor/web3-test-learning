// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleERC20} from "./D45_SimpleERC20.sol";
import {SimpleAMMXYK} from "./D45_SimpleAMMXYK.sol";

contract D45_SpotOracleLendingVuln {
    SimpleERC20 public immutable collateral; // token0
    SimpleERC20 public immutable debt; // token1
    SimpleAMMXYK public immutable amm;

    // 50% LTV：最多借 “抵押价值的一半”
    uint256 public constant LTV_BPS = 5000; // 50%
    uint256 public constant BPS = 10_000;

    mapping(address => uint256) public collateralOf;
    mapping(address => uint256) public debtOf;

    error ExceedsBorrowLimit(uint256 want, uint256 max);

    constructor(SimpleERC20 _collateral, SimpleERC20 _debt, SimpleAMMXYK _amm) {
        collateral = _collateral;
        debt = _debt;
        amm = _amm;
    }

    function depositCollateral(uint256 amount) external {
        collateral.transferFrom(msg.sender, address(this), amount);
        collateralOf[msg.sender] += amount;
    }

    // 核心漏洞：maxBorrow 直接使用 AMM 的 spot price（可被操纵）
    function maxBorrow(address user) public view returns (uint256) {
        uint256 price0In1 = amm.spotPrice0In1(); // 1e18 scale
        uint256 valueInDebt = (collateralOf[user] * price0In1) / 1e18;
        return (valueInDebt * LTV_BPS) / BPS;
    }

    function borrow(uint256 amount) external {
        uint256 maxB = maxBorrow(msg.sender);
        if (debtOf[msg.sender] + amount > maxB)
            revert ExceedsBorrowLimit(amount, maxB);
        debtOf[msg.sender] += amount;
        debt.transfer(msg.sender, amount);
    }
}
