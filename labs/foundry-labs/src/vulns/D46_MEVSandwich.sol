// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(address, address, uint256) external returns (bool);

    function approve(address, uint256) external returns (bool);
}

contract SimpleERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n, string memory s) {
        name = n;
        symbol = s;
    }

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    function approve(address spender, uint256 amt) external returns (bool) {
        allowance[msg.sender][spender] = amt;
        return true;
    }

    function transfer(address to, uint256 amt) external returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amt
    ) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amt;
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        return true;
    }
}

/// @notice 极简 x*y=k AMM（无手续费，方便理解）
contract SimpleAMMXYK_D46 {
    SimpleERC20 public tokenA;
    SimpleERC20 public tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

    error Expired(uint256 nowTs, uint256 deadline);
    error Slippage(uint256 out, uint256 minOut);

    constructor(SimpleERC20 a, SimpleERC20 b) {
        tokenA = a;
        tokenB = b;
    }

    function init(uint256 aAmt, uint256 bAmt) external {
        // 直接把初始储备转进来
        require(reserveA == 0 && reserveB == 0, "inited");
        tokenA.transferFrom(msg.sender, address(this), aAmt);
        tokenB.transferFrom(msg.sender, address(this), bAmt);
        reserveA = aAmt;
        reserveB = bAmt;
    }

    function quoteOutAtoB(uint256 amountInA) public view returns (uint256) {
        // out = reserveB - k/(reserveA + in)
        uint256 k = reserveA * reserveB;
        uint256 newReserveA = reserveA + amountInA;
        uint256 newReserveB = k / newReserveA;
        return reserveB - newReserveB;
    }

    function quoteOutBtoA(uint256 amountInB) public view returns (uint256) {
        uint256 k = reserveA * reserveB;
        uint256 newReserveB = reserveB + amountInB;
        uint256 newReserveA = k / newReserveB;
        return reserveA - newReserveA;
    }

    /// @notice 漏洞版：无 minOut / deadline，易被夹子
    function swapExactInVuln_AtoB(
        uint256 amountInA
    ) external returns (uint256 outB) {
        outB = quoteOutAtoB(amountInA);

        tokenA.transferFrom(msg.sender, address(this), amountInA);
        tokenB.transfer(msg.sender, outB);

        reserveA += amountInA;
        reserveB -= outB;
    }

    /// @notice 修复版：加 minOut + deadline
    function swapExactIn_AtoB(
        uint256 amountInA,
        uint256 minOutB,
        uint256 deadline
    ) external returns (uint256 outB) {
        if (block.timestamp > deadline)
            revert Expired(block.timestamp, deadline);

        outB = quoteOutAtoB(amountInA);
        if (outB < minOutB) revert Slippage(outB, minOutB);

        tokenA.transferFrom(msg.sender, address(this), amountInA);
        tokenB.transfer(msg.sender, outB);

        reserveA += amountInA;
        reserveB -= outB;
    }

    /// @notice 反向：B->A（给 attacker back-run 用）
    /// @notice 反向：B->A（给 attacker back-run 用）
    function swapExactIn_BtoA(
        uint256 amountInB
    ) external returns (uint256 outA) {
        outA = quoteOutBtoA(amountInB);

        tokenB.transferFrom(msg.sender, address(this), amountInB);
        tokenA.transfer(msg.sender, outA);

        reserveB += amountInB;
        reserveA -= outA;
    }
}
