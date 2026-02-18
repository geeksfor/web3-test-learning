# 2026-02-18 - D25：DoS（gas grief / 大循环）：数组无限增长导致关键函数不可用

tags: [solidity, foundry, security, dos, gas, griefing, unbounded-loop, pagination]

## 背景 / 目标

今天目标是复现一类非常常见的合约 DoS：**gas grief / unbounded loop**。

- 漏洞模式：`array` 可以无限增长 + 关键函数对 `array` 做全量循环（O(n)）
- 结果：随着 `array.length` 变大，关键函数最终会因为 **Out Of Gas** 而永远不可用
- 今日产出：
  1) 漏洞合约（Vuln）与修复合约（Fixed：分页/游标）
  2) Foundry 测试：展示“达到阈值后必失败”
  3) 审计视角 Checklist
  4) 记录今日问答（expectRevert / gas 调用 / makeAddr / pure 等）

---

## 原理：为什么会 DoS？

### 1) Gas 上限与 O(n) 循环

EVM 执行每笔交易有 gas 上限（现实还受区块 gas limit 影响）。  
如果某个关键函数的 gas 开销随着 `array.length` 线性增长：

```solidity
for (uint256 i = 0; i < users.length; i++) {
    // 做一些昂贵操作（尤其是 SSTORE / 外部调用）
}
```

那么当 `users.length` 增长到某个阈值后，函数将无法在限制内跑完，直接 **OutOfGas**，从而造成 DoS。

### 2) 为什么 “分页” 也可能 OOG？

分页（pagination/cursor）把 O(n) 拆成多次小 O(k)。  
但如果每次 chunk 里仍然做了大量昂贵操作（例如多次 **0→非0 的 SSTORE**），chunk 也可能在某个 `gasCap` 下爆掉。

> 今日实测：`distributeChunk(1, 30)` 在 `gas: 200000` 下 OOG  
> 根因：循环体对 mapping 进行写入，0→非0 的 SSTORE 很贵；30 次写入轻松超过 200k。

---

## 实现步骤（建议按这个顺序做）

1. 写 Vuln 合约：`participants` 可无限增长；`distribute()` 全量循环写 storage（模拟现实的“发奖励/结算/更新状态”）
2. 写 Fixed 合约：增加 `cursor`，提供 `distributeChunk(amountEach, maxIters)` 分批处理
3. 写测试：
   - small 时 Vuln 可用
   - 固定 gasCap 下，随着人数增加，Vuln 终会失败（阈值）
   - Fixed 在固定 gasCap 下可以持续推进（注意把 `maxIters` 调到能跑过的安全值，或用 probe 自动探测）

---

## 核心代码（示例）

### 1) 漏洞合约：无限增长数组 + 全量循环

```solidity
contract D25_GasGriefVuln {
    address public owner;
    address[] public participants;
    mapping(address => uint256) public credits;

    function register() external {
        participants.push(msg.sender);
    }

    function distribute(uint256 amountEach) external {
        require(msg.sender == owner, "NotOwner");
        for (uint256 i = 0; i < participants.length; i++) {
            credits[participants[i]] += amountEach; // SSTORE: 昂贵
        }
    }
}
```

### 2) 修复合约：分页/游标（cursor）

```solidity
contract D25_GasGriefFixed_Pagination {
    address public owner;
    address[] public participants;
    mapping(address => uint256) public credits;

    uint256 public cursor;

    function register() external {
        participants.push(msg.sender);
    }

    function distributeChunk(uint256 amountEach, uint256 maxIters) external {
        require(msg.sender == owner, "NotOwner");
        require(cursor < participants.length, "NothingToProcess");

        uint256 end = cursor + maxIters;
        if (end > participants.length) end = participants.length;

        for (uint256 i = cursor; i < end; i++) {
            credits[participants[i]] += amountEach;
        }

        cursor = end;
    }
}
```

---

## Foundry 测试要点

### 1) “达到阈值后必失败”的正确写法

#### ✅ 推荐：用低级 `call{gas: gasCap}` 探测 ok / fail

原因：`vm.expectRevert()` **要求下一次调用必须 revert**，不适合“在 while 里多次探测”（没 revert 就直接让测试失败）。

探测写法示意：

```solidity
(bool ok, ) = address(vuln).call{gas: gasCap}(
    abi.encodeWithSelector(vuln.distribute.selector, amountEach)
);
if (!ok) {
    // 达到阈值：固定 gasCap 下开始失败
}
```

#### ⚠️ 不推荐：在“可能成功”的探测轮次里用 `vm.expectRevert()`

```solidity
vm.expectRevert();
vuln.distribute{gas: gasCap}(amountEach);
```

如果这次调用没 revert，测试会直接 FAIL。

---

## 今日运行结果（记录）

你贴出的 trace：

- Fixed 分页版本在 `gasCap = 200000` + `maxIters = 30` 时 OOG：

```
D25_GasGriefFixed_Pagination::distributeChunk(1, 30)
└─ ← [OutOfGas]
```

- Vuln 版本在固定 gasCap 下阈值约为 50：

```
threshold participants (approx): 50
```

### 结论与修复动作

- 分页 chunk 也要控制工作量（`maxIters`），否则 chunk 仍会 OOG
- 建议：
  - 调小 `maxIters`（例如 5~10）
  - 或写一个 probe，自动找到 `gasCap` 下可跑过的最大 iters

---

## 审计视角 Checklist（看到就警觉）

- [ ] **可增长集合**：`address[]` / `bytes[]` / `EnumerableSet` 等
- [ ] 外部用户可触发增长（`push/add`），且 **无上限/无清理**
- [ ] 关键函数存在 **全量遍历**（O(n)）且必须一次性完成（settle/finalize/distribute/snapshot）
- [ ] 循环体做了昂贵操作：
  - [ ] `SSTORE`（写 mapping/数组）
  - [ ] 外部调用（`call/transfer`，甚至调用不受控合约）
  - [ ] 大量 `emit`
- [ ] 缺少分页/游标、缺少 pull-claim 机制
- [ ] 失败会阻断关键路径（例如无法结算、无法分发奖励、无法 finalize）

常见修复优先级：
1. **Pull over Push**（用户自己 claim）✅最稳
2. **Pagination / Cursor**（分批处理）
3. 对集合增长加上合理上限（有业务约束时）

---

## 今日 Q&A（把你问到的点整理进来）

### Q1：如果没有发生 revert，`vm.expectRevert` 会返回错误吗？
会。`vm.expectRevert()` 的语义是：**下一次调用必须 revert**。  
若没 revert，测试直接 FAIL（不会“返回 false”，而是报错失败）。

### Q2：while 循环里多次还没达到 gasCap、没 revert，为什么测试还能跑通？
如果你在这些“可能成功”的探测轮次里写了 `expectRevert`，测试不可能继续（会当场失败）。  
所以“阈值探测”应使用 `call{gas: ...}` 捕获 ok/fail，而不是 expectRevert。

### Q3：`makeAddr(string(abi.encodePacked("p", vm.toString(i))))` 是什么意思？
作用：在循环里生成一批 **可读、确定性、不重复** 的测试地址。

- `vm.toString(i)`：把数字 i 转成字符串（"0","1"...）
- `abi.encodePacked("p", "...")`：拼成 bytes（"p0","p1"...）
- `string(...)`：转回 string
- `makeAddr("p123")`：根据 label 派生地址，并给地址打 label（trace 更好看）

等价更简洁写法：`makeAddr(string.concat("p", vm.toString(i)))`

### Q4：`vuln.distribute{gas: gasCap}(amountEach);` 为什么能这样调用？不是 payable 也行？
`{gas: ...}` 是**限制本次外部调用可用 gas**，与 `payable` 无关。  
`payable` 只影响能否带 `{value: ...}` 转 ETH。

- ✅ 可以：`foo{gas: 200_000}()`
- ❌ 需要 payable：`foo{value: 1 ether}()`（目标函数/合约必须 payable）

### Q5：函数声明 `pure` 是什么意思？
`pure` 表示：**不读也不写链上状态**（只做纯计算）。

- 不能读 `storage` 状态变量
- 不能读 `msg.sender / block.timestamp` 等环境变量
- 只能用参数、局部变量、常量进行计算

对比：
- `view`：可读状态但不写
- 默认：可读可写

---

## 运行命令（示例）

```bash
forge test --match-contract D25_GasGrief_Test -vvv
```

---

## TODO（可选增强）

- [ ] 把 Fixed 的测试改成“自动探测 safeIters”
- [ ] 增加 Pull-claim 版修复（`distribute` 只记账，用户自己 `claim()`）
- [ ] 把循环体换成外部调用，演示“恶意接收者回退函数消耗 gas”导致 griefing 的变体
