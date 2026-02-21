// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleERC20} from "../mocks/SimpleERC20.sol";

contract D44_SlippageWithMinOut {
    error Slippage(uint256 out, uint256 minOut);
    error Expired(uint256 nowTs, uint256 deadline);

    SimpleERC20 public token0;
    SimpleERC20 public token1;

    uint112 public reserve0;
    uint112 public reserve1;

    constructor(SimpleERC20 _t0, SimpleERC20 _t1) {
        token0 = _t0;
        token1 = _t1;
    }

    function _update(uint256 r0, uint256 r1) internal {
        require(r0 <= type(uint112).max && r1 <= type(uint112).max, "overflow");
        reserve0 = uint112(r0);
        reserve1 = uint112(r1);
    }

    function addLiquidity(uint256 amount0, uint256 amount1) external {
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
        _update(uint256(reserve0) + amount0, uint256(reserve1) + amount1);
    }

    function quoteOut(
        address tokenIn,
        uint256 amountIn
    ) public view returns (uint256) {
        bool in0 = tokenIn == address(token0);
        require(in0 || tokenIn == address(token1), "bad token");

        uint256 r0 = uint256(reserve0);
        uint256 r1 = uint256(reserve1);

        if (in0) return (amountIn * r1) / (r0 + amountIn);
        return (amountIn * r0) / (r1 + amountIn);
    }

    function swapExactIn(
        address tokenIn,
        uint256 amountIn,
        uint256 minOut,
        uint256 deadline,
        address to
    ) external returns (uint256 amountOut) {
        if (block.timestamp > deadline)
            revert Expired(block.timestamp, deadline);

        amountOut = quoteOut(tokenIn, amountIn);
        if (amountOut < minOut) revert Slippage(amountOut, minOut);

        bool in0 = tokenIn == address(token0);
        if (in0) {
            token0.transferFrom(msg.sender, address(this), amountIn);
            token1.transfer(to, amountOut);
            _update(
                uint256(reserve0) + amountIn,
                uint256(reserve1) - amountOut
            );
        } else {
            token1.transferFrom(msg.sender, address(this), amountIn);
            token0.transfer(to, amountOut);
            _update(
                uint256(reserve0) - amountOut,
                uint256(reserve1) + amountIn
            );
        }
    }
}
