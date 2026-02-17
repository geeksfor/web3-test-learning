// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./D23_MockERC20.sol";
import "./SimpleAMM.sol";

/// @title SpotOracleLending (vulnerable)
/// @notice Borrow token0 (USD) against token1 (ETH) collateral, using AMM SPOT price as oracle.
///         This is intentionally vulnerable to flash-loan-driven price manipulation.
contract SpotOracleLending {
    MockERC20 public immutable usd; // token0
    MockERC20 public immutable eth; // token1
    SimpleAMM public immutable amm;

    uint256 public immutable ltvBps; // e.g. 5000 = 50%

    /// collateralEth[user]：用户存了多少 ETH 作为抵押
    mapping(address => uint256) public collateralEth;
    /// debtUsd[user]：用户已经借了多少 USD（欠款）
    mapping(address => uint256) public debtUsd;

    event DepositCollateral(address indexed user, uint256 ethAmount);
    event Borrow(address indexed user, uint256 usdAmount);

    error ZeroAmount();
    error ExceedsBorrowLimit(uint256 want, uint256 limit);

    constructor(
        MockERC20 _usd,
        MockERC20 _eth,
        SimpleAMM _amm,
        uint256 _ltvBps
    ) {
        usd = _usd;
        eth = _eth;
        amm = _amm;
        ltvBps = _ltvBps;
    }

    function priceUsdPerEth() public view returns (uint256) {
        // SPOT price from AMM reserves (vulnerable)
        return amm.spotPrice0Per1(); // 1 ETH worth how many USD (1e18 scaled)
    }

    function maxBorrowUsd(address user) public view returns (uint256) {
        uint256 p = priceUsdPerEth(); // 1e18
        // collateral value in USD = ethAmt * p / 1e18
        uint256 valueUsd = (collateralEth[user] * p) / 1e18;
        return (valueUsd * ltvBps) / 10_000;
    }

    function depositEth(uint256 ethAmount) external {
        if (ethAmount == 0) revert ZeroAmount();
        eth.transferFrom(msg.sender, address(this), ethAmount);
        collateralEth[msg.sender] += ethAmount;
        emit DepositCollateral(msg.sender, ethAmount);
    }

    function borrowUsd(uint256 usdAmount) external {
        if (usdAmount == 0) revert ZeroAmount();
        uint256 limit = maxBorrowUsd(msg.sender);
        uint256 newDebt = debtUsd[msg.sender] + usdAmount;
        if (newDebt > limit) revert ExceedsBorrowLimit(newDebt, limit);

        debtUsd[msg.sender] = newDebt;
        usd.transfer(msg.sender, usdAmount);
        emit Borrow(msg.sender, usdAmount);
    }

    // helper for tests (protocol TVL in USD token)
    function usdLiquidity() external view returns (uint256) {
        return usd.balanceOf(address(this));
    }
}
