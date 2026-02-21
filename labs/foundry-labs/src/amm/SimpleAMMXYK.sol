// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(address, address, uint256) external returns (bool);
}

contract SimpleAMMXYK {
    IERC20Like public immutable token0;
    IERC20Like public immutable token1;

    uint112 public reserve0;
    uint112 public reserve1;

    // fee: 0.3% => feeBps=30 (bps=1/10000)
    uint16 public immutable feeBps;

    error ZeroAmount();
    error InsufficientLiquidity();
    error SlippageTooHigh(uint256 out, uint256 minOut);

    event Sync(uint112 r0, uint112 r1);
    event Swap(
        address indexed sender,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        address indexed to
    );

    constructor(address _token0, address _token1, uint16 _feeBps) {
        token0 = IERC20Like(_token0);
        token1 = IERC20Like(_token1);
        feeBps = _feeBps; // 0 for no-fee minimal; 30 for 0.3%
    }

    function _syncFromBalances() internal {
        uint256 b0 = token0.balanceOf(address(this));
        uint256 b1 = token1.balanceOf(address(this));
        reserve0 = uint112(b0);
        reserve1 = uint112(b1);
        emit Sync(reserve0, reserve1);
    }

    /// @dev 最小“加流动性”：直接把币转进来后 sync（不做 LP token）
    function seed(uint256 amount0, uint256 amount1) external {
        if (amount0 == 0 || amount1 == 0) revert ZeroAmount();
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
        _syncFromBalances();
    }

    /// @notice 用 token0 换 token1
    function swap0For1(
        uint256 amountIn,
        uint256 minOut,
        address to
    ) external returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();

        // 1) 收 token0
        token0.transferFrom(msg.sender, address(this), amountIn);

        // 2) 计算有效入金（扣手续费）
        uint256 amountInAfterFee = (amountIn * (10_000 - feeBps)) / 10_000;

        // 3) x*y=k 定价
        // amountOut = y - k/(x+dx)
        uint256 x = uint256(reserve0);
        uint256 y = uint256(reserve1);
        uint256 k = x * y;

        uint256 xNew = x + amountInAfterFee;
        uint256 yNew = k / xNew;
        amountOut = y - yNew;

        if (amountOut == 0) revert InsufficientLiquidity();
        if (amountOut < minOut) revert SlippageTooHigh(amountOut, minOut);

        // 4) 付出 token1
        token1.transfer(to, amountOut);

        // 5) 更新储备（以余额为准，避免“储备与真实余额不一致”）
        _syncFromBalances();

        emit Swap(msg.sender, address(token0), amountIn, amountOut, to);
    }

    /// @notice 用 token1 换 token0（对称）
    function swap1For0(
        uint256 amountIn,
        uint256 minOut,
        address to
    ) external returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();

        token1.transferFrom(msg.sender, address(this), amountIn);

        uint256 amountInAfterFee = (amountIn * (10_000 - feeBps)) / 10_000;

        uint256 x = uint256(reserve0);
        uint256 y = uint256(reserve1);
        uint256 k = x * y;

        uint256 yNew = y + amountInAfterFee;
        uint256 xNew = k / yNew;
        amountOut = x - xNew;

        if (amountOut == 0) revert InsufficientLiquidity();
        if (amountOut < minOut) revert SlippageTooHigh(amountOut, minOut);

        token0.transfer(to, amountOut);
        _syncFromBalances();

        emit Swap(msg.sender, address(token1), amountIn, amountOut, to);
    }
}
