// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {SimpleAMMXYKFee} from "../../src/vulns/D47_SimpleAMMXYKFee.sol";

contract MockERC20 is Test {
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

/// @notice Handler：提供给 fuzzer 随机调用的“动作集合”
contract AMMHandler is Test {
    SimpleAMMXYKFee public amm;
    MockERC20 public t0;
    MockERC20 public t1;

    address public actor;

    constructor(SimpleAMMXYKFee _amm, MockERC20 _t0, MockERC20 _t1) {
        amm = _amm;
        t0 = _t0;
        t1 = _t1;

        actor = makeAddr("actor");

        // 给 actor 铸一些 token，供 swap 用
        t0.mint(actor, 1_000_000 ether);
        t1.mint(actor, 1_000_000 ether);

        vm.startPrank(actor);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function swap0For1(uint256 amtIn) external {
        // 限制 fuzz 范围，避免把池子直接打空或溢出
        amtIn = bound(amtIn, 1e6, 1_000 ether);

        vm.startPrank(actor);
        amm.swapExactIn(address(t0), amtIn);
        vm.stopPrank();
    }

    function swap1For0(uint256 amtIn) external {
        amtIn = bound(amtIn, 1e6, 1_000 ether);

        vm.startPrank(actor);
        amm.swapExactIn(address(t1), amtIn);
        vm.stopPrank();
    }
}

contract D47_KInvariant_Test is StdInvariant, Test {
    MockERC20 t0;
    MockERC20 t1;
    SimpleAMMXYKFee amm;
    AMMHandler handler;

    function setUp() public {
        // 1) 部署 token（给状态变量赋值，别写成局部变量）
        t0 = new MockERC20("T0", "T0");
        t1 = new MockERC20("T1", "T1");

        // 2) 部署 AMM
        amm = new SimpleAMMXYKFee(IERC20(address(t0)), IERC20(address(t1)), 30);

        // 初始化池子储备：先把币“转进池子”，再 init 设置储备
        t0.mint(address(this), 10_000 ether);
        t1.mint(address(this), 10_000 ether);
        t0.transfer(address(amm), 10_000 ether);
        t1.transfer(address(amm), 10_000 ether);
        amm.init(10_000 ether, 10_000 ether);

        handler = new AMMHandler(amm, t0, t1);

        // 告诉 StdInvariant：随机调用 handler 里的函数
        targetContract(address(handler));

        // 只 fuzz 这两个函数（更可控）
        // ✅ 先声明 selectors
        // bytes4;
        // selectors[0] = AMMHandler.swap0For1.selector;
        // selectors[1] = AMMHandler.swap1For0.selector;

        // targetSelector(
        //     FuzzSelector({addr: address(handler), selectors: selectors})
        // );
    }

    /// @notice D47：k 不应下降（考虑 rounding 容忍）
    function invariant_k_should_not_decrease() public {
        (uint256 r0, uint256 r1) = amm.getReserves();
        uint256 kNow = r0 * r1;

        // 关键：我们需要一个“下界”。最简单做法：
        // - 记录初始 k0，要求 kNow >= k0 - tol
        // 但更严格的做法是“每一步都不下降”。Foundry invariant 不好直接拿上一步值，
        // 所以实践里常用：kNow 不低于初始值（fee 模型下应成立）。
        //
        // 若你想实现“逐步不下降”，可以把 kBefore/kAfter 逻辑放进 swap 中（见下方增强版建议）。

        uint256 k0 = (10_000 ether) * (10_000 ether);

        // rounding 容忍：给一点点余量（按你实现的整除误差调整）
        uint256 tol = 1e12; // 只是示例：你可按实际 rounding 调整/缩小

        assertGe(kNow + tol, k0, "k dropped below initial (unexpected)");
    }
}
