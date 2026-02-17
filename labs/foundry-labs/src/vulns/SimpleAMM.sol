// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./D23_MockERC20.sol";

/// @title SimpleAMM (x*y=k) - learning only
/// @notice Constant product AMM with 0.3% fee (997/1000). Assumes both tokens are 18 decimals for simplicity.
contract SimpleAMM {
    MockERC20 public immutable token0; // e.g. USD
    MockERC20 public immutable token1; // e.g. ETH

    uint256 public reserve0;
    uint256 public reserve1;

    event Sync(uint256 reserve0, uint256 reserve1);
    event Swap(
        address indexed sender,
        address indexed inToken,
        uint256 amountIn,
        address indexed outToken,
        uint256 amountOut
    );

    error ZeroAmount();
    error InsufficientLiquidity();

    constructor(MockERC20 _token0, MockERC20 _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    // 往池子里存钱
    function addLiquidity(uint256 amt0, uint256 amt1) external {
        if (amt0 == 0 || amt1 == 0) revert ZeroAmount();
        token0.transferFrom(msg.sender, address(this), amt0);
        token1.transferFrom(msg.sender, address(this), amt1);
        reserve0 += amt0;
        reserve1 += amt1;
        emit Sync(reserve0, reserve1);
    }

    /// @notice spot price: token0 per 1 token1, scaled 1e18 (USD/ETH)
    function spotPrice0Per1() public view returns (uint256) {
        if (reserve1 == 0) revert InsufficientLiquidity();
        return (reserve0 * 1e18) / reserve1;
    }

    /// @notice swap exact input
    /// @param inToken address(token0) or address(token1)
    /// @param amountIn amount of inToken
    /// @return amountOut amount of the other token
    function swapExactIn(
        address inToken,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();

        bool in0 = inToken == address(token0);
        if (!in0 && inToken != address(token1)) revert("bad token");

        (MockERC20 inT, MockERC20 outT, uint256 rIn, uint256 rOut) = in0
            ? (token0, token1, reserve0, reserve1)
            : (token1, token0, reserve1, reserve0);

        // pull in
        inT.transferFrom(msg.sender, address(this), amountIn);

        // apply fee: amountInWithFee = amountIn * 997 / 1000
        uint256 amountInWithFee = (amountIn * 997) / 1000;

        // constant product out: out = rOut * amountInWithFee / (rIn + amountInWithFee)
        amountOut = (rOut * amountInWithFee) / (rIn + amountInWithFee);

        // update reserves
        if (in0) {
            reserve0 = rIn + amountIn;
            reserve1 = rOut - amountOut;
        } else {
            reserve1 = rIn + amountIn;
            reserve0 = rOut - amountOut;
        }

        // send out
        outT.transfer(msg.sender, amountOut);

        emit Swap(msg.sender, address(inT), amountIn, address(outT), amountOut);
        emit Sync(reserve0, reserve1);
    }
}
