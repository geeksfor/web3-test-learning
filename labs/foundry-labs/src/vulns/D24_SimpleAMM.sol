// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./D24_SimpleERC20.sol";

contract SimpleAMM {
    error Slippage(uint256 out, uint256 minOut);
    error Expired(uint256 nowTs, uint256 deadline);
    error InvalidToken();

    SimpleERC20 public immutable token0;
    SimpleERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    // fee: 0.3% => multiply by 997/1000
    uint256 private constant FEE_NUM = 997;
    uint256 private constant FEE_DEN = 1000;

    constructor(SimpleERC20 _t0, SimpleERC20 _t1) {
        token0 = _t0;
        token1 = _t1;
    }

    function addLiquidity(uint256 amount0, uint256 amount1) external {
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
        _sync();
    }

    function _sync() internal {
        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 rIn,
        uint256 rOut
    ) public pure returns (uint256) {
        // amountInWithFee = amountIn * 997
        uint256 amountInWithFee = amountIn * FEE_NUM;
        // out = (amountInWithFee * rOut) / (rIn*1000 + amountInWithFee)
        return (amountInWithFee * rOut) / (rIn * FEE_DEN + amountInWithFee);
    }

    // --------------------------
    // VULN: 没有 minOut
    // --------------------------
    function swapExactIn_NoMinOut(
        address tokenIn,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        bool in0 = (tokenIn == address(token0));
        bool in1 = (tokenIn == address(token1));
        if (!in0 && !in1) revert InvalidToken();

        SimpleERC20 tIn = in0 ? token0 : token1;
        SimpleERC20 tOut = in0 ? token1 : token0;

        uint256 rIn = in0 ? reserve0 : reserve1;
        uint256 rOut = in0 ? reserve1 : reserve0;

        tIn.transferFrom(msg.sender, address(this), amountIn);

        amountOut = getAmountOut(amountIn, rIn, rOut);

        tOut.transfer(msg.sender, amountOut);

        _sync();
    }

    // --------------------------
    // FIX: 加 minOut + deadline
    // --------------------------
    function swapExactIn(
        address tokenIn,
        uint256 amountIn,
        uint256 minOut,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        if (block.timestamp > deadline)
            revert Expired(block.timestamp, deadline);

        bool in0 = (tokenIn == address(token0));
        bool in1 = (tokenIn == address(token1));
        if (!in0 && !in1) revert InvalidToken();

        SimpleERC20 tIn = in0 ? token0 : token1;
        SimpleERC20 tOut = in0 ? token1 : token0;

        uint256 rIn = in0 ? reserve0 : reserve1;
        uint256 rOut = in0 ? reserve1 : reserve0;

        tIn.transferFrom(msg.sender, address(this), amountIn);

        amountOut = getAmountOut(amountIn, rIn, rOut);
        if (amountOut < minOut) revert Slippage(amountOut, minOut);

        tOut.transfer(msg.sender, amountOut);

        _sync();
    }
}
