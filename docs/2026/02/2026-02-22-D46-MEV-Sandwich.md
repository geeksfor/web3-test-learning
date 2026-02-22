# D46：MEV/夹子（Sandwich）简化复现：先交易改变价格再执行 victim

> 日期：2026-02-22  
> 关键词：MEV / Sandwich / Front-run / Back-run / Mempool / x*y=k / Slippage / minOut / deadline  

---

## 1. 这节课要解决什么问题？

**目标：**用一个最小 AMM（恒定乘积 x*y=k）复现“夹子（Sandwich）”三笔交易结构，并写测试断言：

- 攻击者先交易改变价格（front-run）
- victim 按更差价格成交（victim fill gets worse）
- 攻击者再反向交易吃回价格并获利（back-run）
- 修复：victim 带上 **minOut + deadline** 后，夹子导致的坏价应触发 **revert**

---

## 2. 知识点与原理（通俗版）

### 2.1 什么是 MEV？
**MEV（Maximal Extractable Value）** 可以理解为：

> 谁能更早/更巧地把交易塞进区块，就能从别人交易里“榨取”额外价值。

在公链里，你的交易通常会先出现在 **mempool（公共待打包池）**，别人能看到你即将执行的 swap，于是通过插队/重排来获利。

### 2.2 什么是夹子（Sandwich Attack）？
夹子是 MEV 中最典型的一类：

1) **Front-run（抢跑）**：攻击者在 victim 前面先 swap，把池子价格推坏  
2) **Victim（受害者）**：victim 仍按原计划 swap，但实际成交变差（拿到更少 out）  
3) **Back-run（夹后）**：攻击者在 victim 后面反向 swap，把价格吃回来并锁定利润

### 2.3 为什么 victim 的实际成交会恶化？
以恒定乘积 AMM 为例：

- 池子里有 `reserveA` 与 `reserveB`  
- 价格与储备比例相关（简化理解：A 多则 A 更便宜，B 多则 B 更便宜）
- 攻击者的大额 swap 会显著改变储备比例，使 victim 后续同样的 `amountIn` 得到更少的 `amountOut`

因此在测试里我们可以做对比断言：

- **无夹子**：victimOut_base  
- **有夹子**：victimOut_sandwich  
- 结论：`victimOut_sandwich < victimOut_base`

---

## 3. 通过本案例你能学到什么？

- ✅ 夹子攻击的三笔交易结构（front-run / victim / back-run）在测试里如何复现  
- ✅ 如何在测试中量化“victim 实际成交恶化”（对比 out）  
- ✅ 根因不是“合约被黑”，而是 **交易缺少用户侧保护参数**  
- ✅ 修复手段：**minOut（最小输出）+ deadline（过期时间）**；更强的方案是 TWAP/预言机/私有交易通道  

---

## 4. 最小复现实验设计

### 4.1 实验环境（最小 AMM）
- 两个最小 ERC20：TokenA / TokenB  
- 一个最小 x*y=k AMM：
  - `quoteOutAtoB(amountInA)` 计算预期输出  
  - 漏洞版 swap：`swapExactInVuln_AtoB(amountInA)`（无保护）
  - 修复版 swap：`swapExactIn_AtoB(amountInA, minOutB, deadline)`
  - 反向 swap：`swapExactIn_BtoA(amountInB)`（给 back-run 用）

### 4.2 三笔交易脚本（夹子）
1) attacker：`A -> B` 大额 swap（推坏价格）  
2) victim：`A -> B` 小额 swap（成交恶化）  
3) attacker：`B -> A` 反向 swap（吃回价格并获利）

---

## 5. 代码（合约）

> 建议路径：`src/vulns/D46_MEVSandwich.sol`

```solidity
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

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
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
        require(reserveA == 0 && reserveB == 0, "inited");
        tokenA.transferFrom(msg.sender, address(this), aAmt);
        tokenB.transferFrom(msg.sender, address(this), bAmt);
        reserveA = aAmt;
        reserveB = bAmt;
    }

    function quoteOutAtoB(uint256 amountInA) public view returns (uint256) {
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
    function swapExactInVuln_AtoB(uint256 amountInA) external returns (uint256 outB) {
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
        if (block.timestamp > deadline) revert Expired(block.timestamp, deadline);

        outB = quoteOutAtoB(amountInA);
        if (outB < minOutB) revert Slippage(outB, minOutB);

        tokenA.transferFrom(msg.sender, address(this), amountInA);
        tokenB.transfer(msg.sender, outB);

        reserveA += amountInA;
        reserveB -= outB;
    }

    /// @notice 反向：B->A（给 attacker back-run 用）
    function swapExactIn_BtoA(uint256 amountInB) external returns (uint256 outA) {
        outA = quoteOutBtoA(amountInB);

        tokenB.transferFrom(msg.sender, address(this), amountInB);
        tokenA.transfer(msg.sender, outA);

        reserveB += amountInB;
        reserveA -= outA;
    }
}
```

---

## 6. 代码（Foundry 测试）

> 建议路径：`test/vulns/D46_MEVSandwich.t.sol`

测试包含三部分：

- `test_sandwich_victim_fill_gets_worse`：夹子下 victim out 变少 + attacker 获利  
- `test_fixed_minOut_reverts_under_sandwich`：修复后夹子导致滑点过大 → revert  
- `test_fixed_deadline_expired_reverts`：deadline 过期 → revert  

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D46_MEVSandwich.sol";

contract D46_MEVSandwich_Test is Test {
    SimpleERC20 tokenA;
    SimpleERC20 tokenB;
    SimpleAMMXYK_D46 amm;

    address lp = makeAddr("lp");
    address victim = makeAddr("victim");
    address attacker = makeAddr("attacker");

    function setUp() public {
        tokenA = new SimpleERC20("TokenA", "A");
        tokenB = new SimpleERC20("TokenB", "B");
        amm = new SimpleAMMXYK_D46(tokenA, tokenB);

        // LP 建池
        tokenA.mint(lp, 2000 ether);
        tokenB.mint(lp, 2000 ether);

        vm.startPrank(lp);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        amm.init(1000 ether, 1000 ether);
        vm.stopPrank();

        // victim 与 attacker 初始资金
        tokenA.mint(victim, 100 ether);
        tokenA.mint(attacker, 1000 ether);

        vm.prank(victim);
        tokenA.approve(address(amm), type(uint256).max);

        vm.prank(attacker);
        tokenA.approve(address(amm), type(uint256).max);

        vm.prank(attacker);
        tokenB.approve(address(amm), type(uint256).max);
    }

    function test_sandwich_victim_fill_gets_worse() public {
        uint256 victimIn = 10 ether;

        // baseline：无夹子 victim 能拿到的 out
        uint256 outBase = amm.quoteOutAtoB(victimIn);

        // 让 victim 真换一次确认（可选）
        vm.startPrank(victim);
        uint256 vB0 = tokenB.balanceOf(victim);
        amm.swapExactInVuln_AtoB(victimIn);
        uint256 outBaseReal = tokenB.balanceOf(victim) - vB0;
        vm.stopPrank();

        assertEq(outBaseReal, outBase, "baseline out should match quote");

        // 重置：为了对比公平，重新 setUp 一次
        setUp();

        // sandwich
        uint256 attackerA_before = tokenA.balanceOf(attacker);

        // 1) front-run：attacker 大额 A->B 推坏价格
        vm.startPrank(attacker);
        uint256 frontIn = 200 ether;
        uint256 aB0 = tokenB.balanceOf(attacker);
        amm.swapExactInVuln_AtoB(frontIn);
        uint256 attackerB_got = tokenB.balanceOf(attacker) - aB0;
        vm.stopPrank();

        // 2) victim 同样的输入，但 out 变少
        uint256 outSandwichQuote = amm.quoteOutAtoB(victimIn);

        vm.startPrank(victim);
        uint256 vB1 = tokenB.balanceOf(victim);
        amm.swapExactInVuln_AtoB(victimIn);
        uint256 outSandwichReal = tokenB.balanceOf(victim) - vB1;
        vm.stopPrank();

        assertEq(outSandwichReal, outSandwichQuote, "sandwich out should match quote");
        assertTrue(outSandwichReal < outBase, "victim fill should be worse under sandwich");

        // 3) back-run：attacker B->A 吃回价格并获利
        vm.startPrank(attacker);
        amm.swapExactIn_BtoA(attackerB_got);
        uint256 attackerA_after = tokenA.balanceOf(attacker);
        vm.stopPrank();

        assertTrue(attackerA_after > attackerA_before, "attacker should profit in simplified sandwich");
    }

    function test_fixed_minOut_reverts_under_sandwich() public {
        uint256 victimIn = 10 ether;

        uint256 outBase = amm.quoteOutAtoB(victimIn);
        uint256 minOut = (outBase * 99) / 100; // 允许 1% 滑点（示例）

        // attacker front-run
        vm.prank(attacker);
        amm.swapExactInVuln_AtoB(200 ether);

        // victim 如果坚持 minOut（基于正常市场预期），夹子下会因为滑点过大而 revert
        vm.startPrank(victim);
        vm.expectRevert(SimpleAMMXYK_D46.Slippage.selector);
        amm.swapExactIn_AtoB(victimIn, minOut, block.timestamp + 60);
        vm.stopPrank();
    }

    function test_fixed_deadline_expired_reverts() public {
        vm.startPrank(victim);
        vm.expectRevert(SimpleAMMXYK_D46.Expired.selector);
        amm.swapExactIn_AtoB(1 ether, 0, block.timestamp - 1);
        vm.stopPrank();
    }
}
```

---

## 7. 审计视角 Checklist（D46）

### 7.1 交易参数保护
- [ ] swap / buy / redeem 是否包含 `minOut` / `maxIn` / `priceLimit`？
- [ ] 是否包含 `deadline`（避免长时间挂单暴露 mempool）？
- [ ] 默认参数是否安全？（例如 `minOut=0` 基本等于无保护）

### 7.2 价格源与关键逻辑
- [ ] 协议关键逻辑（借贷额度、清算、铸造、赎回）是否依赖 **spot price（瞬时现价）**？
- [ ] 是否需要 **TWAP / 预言机** 来降低被操纵风险？
- [ ] 是否存在可被 flash-loan + sandwich 组合放大的路径？

### 7.3 交易通道与抗 MEV
- [ ] 是否建议用户走私有交易（private relay / bundle）或设置较严格的 `minOut`？
- [ ] 是否在 UI/SDK 层默认计算合理 `minOut`（含滑点容忍）？

---

## 8. 如何运行

```bash
cd labs/foundry-labs
forge test --match-contract D46_MEVSandwich_Test -vvv
```

---

## 9. 今日总结（一句话）
夹子并不需要“破坏合约”，它只需要利用 **mempool 可见性 + AMM 价格可被交易瞬时推动**，在 victim 没有 `minOut/deadline` 保护时，让 victim 被动吃坏价并把价差利润转移给攻击者。

