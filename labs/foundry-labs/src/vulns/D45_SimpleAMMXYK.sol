// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleERC20} from "./D45_SimpleERC20.sol";

contract SimpleAMMXYK {
    SimpleERC20 public immutable token0;
    SimpleERC20 public immutable token1;

    uint112 public reserve0;
    uint112 public reserve1;

    error InsufficientLiquidity();
    error BadToken();

    constructor(SimpleERC20 _t0, SimpleERC20 _t1) {
        token0 = _t0;
        token1 = _t1;
    }

    function _update(uint256 r0, uint256 r1) internal {
        // uint112：模拟真实 AMM 用紧凑存储（也让你复习 D43 的“为什么转 uint112”）
        reserve0 = uint112(r0);
        reserve1 = uint112(r1);
    }

    function addLiquidity(uint256 amount0, uint256 amount1) external {
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);

        uint256 r0 = uint256(reserve0) + amount0;
        uint256 r1 = uint256(reserve1) + amount1;
        _update(r0, r1);
    }

    // spot price：用 reserve 比值表示 token0 的“以 token1 计价”
    // 返回值用 1e18 缩放：price = reserve1/reserve0
    function spotPrice0In1() public view returns (uint256) {
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();
        return (uint256(reserve1) * 1e18) / uint256(reserve0);
    }

    // swapExactIn：用 x*y=k 推导 amountOut（无手续费版本）
    function swapExactIn(
        address tokenIn,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        if (tokenIn != address(token0) && tokenIn != address(token1))
            revert BadToken();
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();

        bool inIs0 = tokenIn == address(token0);
        SimpleERC20 inToken = inIs0 ? token0 : token1;
        SimpleERC20 outToken = inIs0 ? token1 : token0;

        uint256 rIn = inIs0 ? uint256(reserve0) : uint256(reserve1);
        uint256 rOut = inIs0 ? uint256(reserve1) : uint256(reserve0);

        inToken.transferFrom(msg.sender, address(this), amountIn);

        // k = rIn * rOut
        uint256 k = rIn * rOut;
        uint256 newRIn = rIn + amountIn;
        uint256 newROut = k / newRIn;
        amountOut = rOut - newROut;

        outToken.transfer(msg.sender, amountOut);

        // 更新储备
        if (inIs0) _update(newRIn, newROut);
        else _update(newROut, newRIn);
    }
}
