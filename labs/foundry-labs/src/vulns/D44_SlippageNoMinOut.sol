// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleERC20} from "../mocks/SimpleERC20.sol";

contract D44_SlippageNoMinOut {
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

    // x*y=k 的最小 swap（无手续费），重点：没有 minOut
    function swapExactIn(
        address tokenIn,
        uint256 amountIn,
        address to
    ) external returns (uint256 amountOut) {
        bool in0 = tokenIn == address(token0);
        require(in0 || tokenIn == address(token1), "bad token");

        if (in0) {
            token0.transferFrom(msg.sender, address(this), amountIn);

            // out = (amountIn * reserve1) / (reserve0 + amountIn)
            uint256 r0 = uint256(reserve0);
            uint256 r1 = uint256(reserve1);
            amountOut = (amountIn * r1) / (r0 + amountIn);

            token1.transfer(to, amountOut);
            _update(r0 + amountIn, r1 - amountOut);
        } else {
            token1.transferFrom(msg.sender, address(this), amountIn);

            uint256 r0 = uint256(reserve0);
            uint256 r1 = uint256(reserve1);
            amountOut = (amountIn * r0) / (r1 + amountIn);

            token0.transfer(to, amountOut);
            _update(r0 - amountOut, r1 + amountIn);
        }
    }

    function quoteOut(
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256) {
        bool in0 = tokenIn == address(token0);
        require(in0 || tokenIn == address(token1), "bad token");

        uint256 r0 = uint256(reserve0);
        uint256 r1 = uint256(reserve1);

        if (in0) return (amountIn * r1) / (r0 + amountIn);
        return (amountIn * r0) / (r1 + amountIn);
    }
}
