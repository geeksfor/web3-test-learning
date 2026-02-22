// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract SimpleAMMXYKFee {
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    // 用 uint112 模仿 UniswapV2 的 reserve 存储（省 gas / packing）
    uint112 public reserve0;
    uint112 public reserve1;

    // 例如 30 = 0.30%
    uint16 public immutable feeBps; // out of 10_000

    error InsufficientLiquidity();
    error BadAmount();

    constructor(IERC20 _token0, IERC20 _token1, uint16 _feeBps) {
        token0 = _token0;
        token1 = _token1;
        feeBps = _feeBps;
    }

    function init(uint256 amount0, uint256 amount1) external {
        // 测试里用：先把 token 转给本合约，然后 init 更新储备
        reserve0 = uint112(amount0);
        reserve1 = uint112(amount1);
    }

    function getReserves() public view returns (uint256 r0, uint256 r1) {
        r0 = reserve0;
        r1 = reserve1;
    }

    function k() external view returns (uint256) {
        return uint256(reserve0) * uint256(reserve1);
    }

    /// @notice 对输入收手续费的 swapExactIn：给定 tokenIn 和 amountIn，换出另一边 tokenOut
    function swapExactIn(
        address tokenIn,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        if (amountIn == 0) revert BadAmount();

        (uint256 r0, uint256 r1) = getReserves();
        if (r0 == 0 || r1 == 0) revert InsufficientLiquidity();

        bool zeroForOne = (tokenIn == address(token0));
        if (!zeroForOne && tokenIn != address(token1)) revert BadAmount();
        // 1) 收输入
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        // 2) 计算扣费后的有效输入
        uint256 amountInAfterFee = (amountIn * (10_000 - feeBps)) / 10_000;

        // 3) x*y=k：amountOut = (amountInAfterFee * rOut) / (rIn + amountInAfterFee)
        if (zeroForOne) {
            // token0 in, token1 out
            amountOut = (amountInAfterFee * r1) / (r0 + amountInAfterFee);
            token1.transfer(msg.sender, amountOut);

            // 4) 更新储备（注意：手续费留在池子里，所以 r0 增加的是 amountIn 全额）
            uint256 newR0 = r0 + amountIn;
            uint256 newR1 = r1 - amountOut;
            reserve0 = uint112(newR0);
            reserve1 = uint112(newR1);
        } else {
            // token1 in, token0 out
            amountOut = (amountInAfterFee * r0) / (r1 + amountInAfterFee);
            token0.transfer(msg.sender, amountOut);

            uint256 newR1 = r1 + amountIn;
            uint256 newR0 = r0 - amountOut;
            reserve0 = uint112(newR0);
            reserve1 = uint112(newR1);
        }
    }
}
