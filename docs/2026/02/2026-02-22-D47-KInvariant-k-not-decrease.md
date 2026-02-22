# D47｜Invariant：k 不应下降（考虑 fee 时的变化规则）

> 目标：给你最小 AMM（x*y=k）补一条 **invariant（不变量）**：在一连串随机 swap 操作后，池子的 `k = reserve0 * reserve1` **不应下降**（考虑手续费与整数舍入的规则）。  
> 工具：Foundry `StdInvariant` + Handler（动作集合）。

---

## 1. 你今天主要做什么

1) 在 AMM（常数乘积池）里明确并实现（或复用）手续费模型（常见是 **fee-on-input**）。  
2) 用 Foundry 的 **invariant 测试**随机执行多次 swap（0→1 / 1→0）。  
3) 断言不变量：`k` 在规则允许的误差范围内 **不会变小**：
- **无手续费（fee=0）**：`k_after` 应当 **≈** `k_before`（允许少量 rounding）
- **有手续费（fee>0，且手续费留在池子里）**：`k_after` 应当 **≥** `k_before`（更不容易下降；仍需少量 rounding 容忍）

> 实战建议：优先做“**每一步 swap 前后 k 不下降**”的断言（更容易定位是哪一步破坏 invariant）。如果你的 `StdInvariant` 写起来不方便保存上一步的 k，可以先用“k 不低于初始 k”作为弱化版本，再逐步加强。

---

## 2. 知识点与原理（通俗版）

### 2.1 什么是 invariant？

- **单元测试**：验证某个具体场景、某组固定输入输出。
- **invariant 测试**：验证一个“长期必须成立的性质”。Fuzzer 会随机调用你提供的动作（handler 函数）很多次，任何一步破坏不变量都算 bug。

在 AMM 中，常见不变量：
- 池子储备不会变成负数/异常
- swap 后 `k` 不应下降（或按手续费模型应增长）
- 资产守恒相关性质（视实现而定）

### 2.2 为什么关注 k = x*y？

常数乘积 AMM 的核心：池子维护两种资产储备 `x` 与 `y`，理想情况下满足：

- 无手续费：swap 让 `x*y` 近似保持不变（整数除法会有 rounding）
- 有手续费且手续费留在池子：池子“更肥”，`x*y` **更倾向于上升**或至少不下降

### 2.3 fee-on-input 的直觉（为什么有 fee 时 k 更不容易下降）

以“对输入收手续费”为例：
- 用户输入 `amountIn`
- 扣掉手续费后参与定价的是 `amountInAfterFee`
- **但手续费那部分 token 并没有消失**，它也进了池子（储备增加）

所以：用户用更少的“有效输入”换出 tokenOut，但把手续费也留给池子，整体上 `k` 更难变小。

> 注意：若你的实现是“手续费被转走（不留在池子）”、或有额外的“协议费”抽走，则 `k` 的规则会不同，需要按你实现的真实模型调整断言。

### 2.4 rounding（舍入）为什么会影响 k？

Solidity 的 `/` 是整数除法，必然存在向下取整：
- `amountOut = (amountInAfterFee * rOut) / (rIn + amountInAfterFee)`  
- 取整会导致 `amountOut` 偏小一点点或偏大一点点（看表达式），从而 `k` 在极小范围波动。

因此 invariant 要给**合理 tolerance（误差容忍）**，但不能太大，否则“真 bug”也会被放过。

---

## 3. 审计视角（Checklist）

### 3.1 k 不变量相关风险点
- [ ] swap 计算公式是否正确（in/out 方向、rIn/rOut、更新顺序）
- [ ] fee 的扣费位置是否一致（fee-on-input / fee-on-output）
- [ ] 手续费是否留在池子（影响 `k` 规则），是否存在协议费抽走
- [ ] reserve 更新是否与实际余额一致（是否可能出现“余额变了但 reserve 没变”）
- [ ] 使用 `uint112`/截断存储 reserve 是否可能溢出/截断（导致 `k` 异常下降）
- [ ] 是否存在 0 流动性、极端输入导致除零、负数（underflow）等边界
- [ ] 是否允许直接 transfer token 到池子导致 reserve/balance 不一致（UniswapV2 需要 `sync`/`skim` 类机制）

### 3.2 Invariant 测试设计风险点（你今天已经踩过的）
- [ ] `selectors` 必须 **分配长度**：`new bytes4[](2)`，否则越界
- [ ] `setUp()` 顺序：先 `new` 合约，再调用它的方法；否则会对 `address(0)` 调用
- [ ] 避免 **shadowing（变量遮蔽）**：`t0 = new ...`，不要写成 `MockERC20 t0 = new ...`（局部变量会遮蔽状态变量）
- [ ] handler 中 fuzz 输入要 `bound()`，避免把池子打空/溢出导致“无意义失败”

---

## 4. 详细步骤（按这个做就能落地）

### Step 0：准备 AMM（带 fee）与两个 ERC20

1) 写/复用一个最小 AMM：维护 `reserve0/reserve1`，提供 `getReserves()`，swap 使用 fee-on-input。  
2) 写两个最小 ERC20（或用你仓库已有的 `SimpleERC20`/OZ）。  
3) 在 `setUp()`：
   - 铸币给测试合约 `address(this)`
   - 把初始流动性转入 AMM
   - init/setReserves

### Step 1：写 Handler（fuzz 的动作集合）

- `swap0For1(uint256 amtIn)`
- `swap1For0(uint256 amtIn)`
- 里面用 `amtIn = bound(amtIn, min, max)` 控制范围  
- 使用 `actor` 地址来执行 `transferFrom`（先 approve）

### Step 2：写 invariant 断言

建议做两层：
- **弱化版**（快速上手）：`kNow >= k0 - tol`（k 不低于初始）
- **加强版**（更贴题、定位更强）：每次 swap 前后都检查 `kAfter + tol >= kBefore`

> 加强版推荐实现方式：在 Handler 里保存 `lastK`，每次 swap 前后做断言并更新。

### Step 3：运行

```bash
cd labs/foundry-labs
forge test --match-contract D47_KInvariant_Test -vvv
```

---

## 5. 参考实现代码（可直接粘贴）

> 说明：下面提供 **最小可用**结构，你可以替换为你仓库中的 token/AMM 文件路径与命名。重点看：fee-on-input、handler、invariant 断言与常见坑修复。

### 5.1 AMM（fee-on-input）核心 swap 公式

```solidity
// 关键：对输入收手续费
uint256 amountInAfterFee = amountIn * (10_000 - feeBps) / 10_000;

// x*y=k：out = (inAfterFee * rOut) / (rIn + inAfterFee)
amountOut = (amountInAfterFee * rOut) / (rIn + amountInAfterFee);

// reserve 更新：rIn 增加 amountIn 全额（手续费留池子），rOut 减少 amountOut
```

### 5.2 Handler：加强版（逐步 k 不下降）

```solidity
contract AMMHandler is Test {
    SimpleAMMXYKFee public amm;
    MockERC20 public t0;
    MockERC20 public t1;

    address public actor;
    uint256 public lastK; // ✅ 保存上一次 k，用于“每一步”不下降断言

    constructor(SimpleAMMXYKFee _amm, MockERC20 _t0, MockERC20 _t1) {
        amm = _amm;
        t0 = _t0;
        t1 = _t1;

        actor = makeAddr("actor");

        t0.mint(actor, 1_000_000 ether);
        t1.mint(actor, 1_000_000 ether);

        vm.startPrank(actor);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        (uint256 r0, uint256 r1) = amm.getReserves();
        lastK = r0 * r1;
    }

    function _assertKNotDown(uint256 kAfter) internal {
        uint256 tol = 1e12; // 依据你的 rounding 调整
        assertGe(kAfter + tol, lastK, "k decreased step-by-step");
        lastK = kAfter;
    }

    function swap0For1(uint256 amtIn) external {
        amtIn = bound(amtIn, 1e6, 1_000 ether);

        vm.startPrank(actor);
        amm.swapExactIn(address(t0), amtIn);
        vm.stopPrank();

        (uint256 r0, uint256 r1) = amm.getReserves();
        _assertKNotDown(r0 * r1);
    }

    function swap1For0(uint256 amtIn) external {
        amtIn = bound(amtIn, 1e6, 1_000 ether);

        vm.startPrank(actor);
        amm.swapExactIn(address(t1), amtIn);
        vm.stopPrank();

        (uint256 r0, uint256 r1) = amm.getReserves();
        _assertKNotDown(r0 * r1);
    }
}
```

### 5.3 StdInvariant：targetContract + selectors（可选）

**最兼容写法**（推荐先用这个，基本不挑 `forge-std` 版本）：

```solidity
targetContract(address(handler));
```

如果你的 `forge-std` 支持 selector 过滤，再用：

```solidity
bytes4[] memory selectors = new bytes4[](2); // ✅ 一定要分配长度
selectors[0] = AMMHandler.swap0For1.selector;
selectors[1] = AMMHandler.swap1For0.selector;

targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
```

---

## 6. 你今天遇到的报错与快速定位（必背）

### 6.1 `Undeclared identifier: selectors`
原因：你写了 `bytes4;` 或没声明 `selectors` 变量。  
修复：

```solidity
bytes4[] memory selectors = new bytes4[](2);
```

### 6.2 `call to non-contract address 0x000...000`（setUp 失败）
原因：你对 **零地址**调用了合约函数（通常是：还没 `new` 就调用，或变量遮蔽导致状态变量仍是 0）。  
修复要点：
- `t0 = new ...`（不要写 `MockERC20 t0 = new ...`）
- 先 `new`，再调用 `.mint/.transfer/.init`
- `handler = new ...` 必须在 `targetContract(address(handler))` 之前

建议在 setUp 里加断言定位：

```solidity
assertTrue(address(t0) != address(0), "t0 is zero");
assertTrue(address(amm) != address(0), "amm is zero");
assertTrue(address(handler) != address(0), "handler is zero");
```

### 6.3 `selectors[0] = ...` 不报编译但运行 panic（数组越界）
原因：`bytes4[] memory selectors;` 没分配长度。  
修复：`new bytes4[](2)`。

---

## 7. 今日收获总结

- 把“单点用例”升级为“系统长期性质”：invariant 思维进入 AMM 场景  
- 明确手续费模型对 `k` 的影响：手续费留池子 => `k` 更不易下降  
- 学会在 fuzz/invariant 里控制输入空间（bound）与容忍 rounding（tolerance）  
- 实战踩坑：selectors 声明/分配、setUp 顺序、zero address、变量遮蔽

---

## 8. 运行命令

```bash
cd labs/foundry-labs
forge test --match-contract D47_KInvariant_Test -vvv
```

