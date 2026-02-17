// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./D22_SimpleERC20.sol";
import "./D22_MockOracle.sol";

/// @notice 简化借贷：
/// - 抵押 COL
/// - 借出 DEBT
/// - maxBorrow = collateral * price * LTV
/// 漏洞点：price 来自可操纵 oracle，未做 TWAP / 多源 / 偏差限制 / 过期校验等
contract D22_VulnerableLending {
    D22_SimpleERC20 public immutable COL;
    D22_SimpleERC20 public immutable DEBT;
    D22_MockOracle public immutable ORACLE;

    // LTV: 例如 0.5e18 = 50%
    uint256 public immutable LTV_WAD;

    mapping(address => uint256) public collateralOf; // COL amount (18d)
    mapping(address => uint256) public debtOf; // DEBT amount (18d)

    event Deposit(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);

    constructor(
        D22_SimpleERC20 col,
        D22_SimpleERC20 debt,
        D22_MockOracle oracle,
        uint256 ltvWad
    ) {
        require(ltvWad <= 1e18, "BAD_LTV");
        COL = col;
        DEBT = debt;
        ORACLE = oracle;
        LTV_WAD = ltvWad;
    }

    function depositCollateral(uint256 amount) external {
        require(amount > 0, "ZERO");
        // 记录用户存了多少抵押物
        collateralOf[msg.sender] += amount;
        // 将抵押人钱转到这个借贷合约中
        require(COL.transferFrom(msg.sender, address(this), amount), "TF_FAIL");
        emit Deposit(msg.sender, amount);
    }

    function maxBorrow(address user) public view returns (uint256) {
        uint256 c = collateralOf[user]; // 18d
        uint256 p = ORACLE.getPrice(); // 18d (DEBT per 1 COL)

        uint256 valueInDebt = (c * p) / 1e18;

        return (valueInDebt * LTV_WAD) / 1e18;
    }

    function borrow(uint256 amount) external {
        require(amount > 0, "ZERO");
        uint256 newDebt = debtOf[msg.sender] + amount;
        require(newDebt <= maxBorrow(msg.sender), "EXCEED_MAX_BORROW");
        debtOf[msg.sender] = newDebt;

        require(DEBT.transfer(msg.sender, amount), "T_FAIL");
        emit Borrow(msg.sender, amount);
    }
}
