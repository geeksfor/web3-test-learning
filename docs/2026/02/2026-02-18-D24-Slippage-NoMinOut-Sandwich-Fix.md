# 2026-02-18 - D24 滑点缺失：swap 没有 minOut（任意价格都成交）+ Sandwich 示例 + 修复

tags: [defi, amm, slippage, sandwich, foundry, solidity, security]

## 今日目标
- 复现漏洞：**swap 接口缺少 `minOut`**，导致用户在“极差价格”下依然成交（业务失败）。
- 写失败测试（vuln）：证明 **“任意价格都成交”**。
- 修复：加入 `minOut`（建议同时加入 `deadline`），并写修复测试：价格过差必须 `revert`。

---

## 1. 背景与原理

### 1.1 滑点（Slippage）是什么？
在 AMM（如 x*y=k）里，价格由池子储备决定。你的交易会改变储备，所以**交易规模越大/池子越浅，价格变化越大**，最终你拿到的 `amountOut` 会比你看到的“预估值”更少——这就是滑点。

### 1.2 为什么 “没有 minOut” 会危险？
如果 swap 只有「固定输入」：
- `swapExactIn(tokenIn, amountIn)`  
但没有：
- `swapExactIn(tokenIn, amountIn, minOut, deadline)`  

那么用户无法表达：“**我最低要拿到多少**”。  
结果是：**只要链上能执行，就会成交** —— 即使成交价格离谱。

> 这类漏洞常见表现不是“合约报错”，而是“交易成功但用户亏得离谱”，因此测试要用“业务失败断言”来体现漏洞。

---

## 2. Sandwich（夹子攻击 / 三明治攻击）解释（今日提问 1）
Sandwich 指攻击者把你的交易夹在两笔自己的交易中间：

1) **Front-run（前置）**：攻击者先交易把价格打歪（让你变得很亏）。  
2) **Victim（你）**：你照常成交（因为没有 `minOut`，或者 `minOut` 设得太松）。  
3) **Back-run（后置）**：攻击者再反向交易把价格打回去并套利。

> `minOut` 不能阻止“夹交易”（排序），但能让你在价格过差时 **revert**，从而避免“被迫以离谱价格成交”。

---

## 3. 费率计算：为什么用乘法系数（今日提问 2）
常见 0.3% 手续费：
- 经济含义：`amountInWithFee = amountIn - amountIn * 0.003`

Solidity 不支持浮点，所以用分数表示：
- `FEE_NUM/FEE_DEN = 997/1000`
- 等价写法：
  - `amountInWithFee = amountIn * 997 / 1000`

Uniswap V2 风格经常把 `/1000`“融入分母”，减少一次除法并保持公式整洁：
- `amountInWithFee = amountIn * 997`
- `out = (amountInWithFee * rOut) / (rIn*1000 + amountInWithFee)`

---

## 4. deadline 参数含义（今日提问 3）
`deadline` 是这笔 swap 的**最晚有效时间**：
- 合约里通常做：
  ```solidity
  if (block.timestamp > deadline) revert Expired(block.timestamp, deadline);
  ```
目的：
- 防止交易在 mempool 挂太久、市场状态变化后还成交。
- 与 `minOut` 搭配：`minOut` 限制价格底线；`deadline` 限制时间窗口。

---

## 5. 区块链交易流程（今日提问 4，简述版）
1) 本地构造交易（to/value/data/gas/nonce）并签名  
2) 广播到节点 → 进入 mempool  
3) 验证者/矿工选择并排序交易打包出块  
4) EVM 按顺序执行：成功则状态生效；revert 则状态回滚但 gas 消耗不退  
5) 区块确认数增加，最终确定性增强（PoS 下还有 finalized）

---

## 6. 实现与代码结构（建议）
- `src/token/SimpleERC20.sol`
- `src/amm/SimpleAMM.sol`
- `test/vulns/D24_NoSlippageProtection.t.sol`（或拆成两个：vuln + fixed）

### 6.1 漏洞接口（没有 minOut）
- `swapExactIn_NoMinOut(tokenIn, amountIn)`  
**特点**：只计算 `amountOut` 并转账，不做任何最小输出约束。

### 6.2 修复接口（加入 minOut + deadline）
- `swapExactIn(tokenIn, amountIn, minOut, deadline)`  
**关键检查**：
- `block.timestamp <= deadline`
- `amountOut >= minOut` 否则 revert `Slippage(out, minOut)`

---

## 7. Foundry 测试设计

### 7.1 失败测试（vuln）：证明“任意价格都成交”
思路：
1) 记录正常情况下 Alice 的预期 `expectedNormal`
2) attacker 先用大额 swap 打歪价格
3) Alice 调用漏洞 swap（无 minOut）仍然成功
4) 断言：`outAfterSandwich` 明显小于 `expectedNormal`（比如少 30% 以上）

> 注意：这里的“失败”是**业务失败**（用户以不可接受价格成交），不是交易 revert。

### 7.2 修复测试（fixed）：价格过差必须 revert
思路：
1) Alice 仍用正常池子计算 `expectedNormal`
2) 设 `minOut = expectedNormal * 99%`（允许 1% 滑点）
3) attacker 打歪价格
4) Alice 带 `minOut` 调用修复函数，应触发 `Slippage` revert
5) 再补一个 deadline 过期测试：`vm.warp` 后应触发 `Expired` revert

---

## 8. 今日排错记录：expectRevert selector 不匹配（今日提问 5）
你遇到的错误形态：
- 实际 revert：`Expired(100, 99)`
- 期望 revert：`custom error 0xaa2fd925`（selector 不一致）

最稳的写法是匹配**完整 revert data**（selector + 参数）：
```solidity
vm.expectRevert(
  abi.encodeWithSelector(SimpleAMM.Expired.selector, 100, 99)
);
```

如果只想匹配 selector：
```solidity
vm.expectRevert(SimpleAMM.Expired.selector);
```
但要确保没有同名 `Expired`、没有导入错合约文件，避免 selector 绑定到别处。

---

## 9. 审计视角（Audit Checklist）

### 9.1 交易保护参数
- [ ] `swapExactIn` 是否提供 `minOut`（或 `amountOutMin`）？
- [ ] 是否提供 `deadline`（或 `validTo`）并检查 `block.timestamp`？
- [ ] 默认参数是否安全？（例如前端是否可能传 0 的 `minOut`）

### 9.2 价格与储备计算
- [ ] `getAmountOut` 是否基于当前储备、并正确处理手续费？
- [ ] 计算中是否存在溢出/精度问题？（Solidity 0.8+ 默认溢出 revert，但要注意乘法顺序）
- [ ] 是否存在“极小额手续费被整数除法舍掉”的意外经济效果？

### 9.3 MEV / Sandwich 风险
- [ ] 合约本身无法阻止交易排序，但应提供让用户自保的参数（`minOut/deadline`）
- [ ] 是否存在可被预言机/价格源操纵导致更严重后果的路径？（借贷、清算、兑换等）

### 9.4 可观测性与可追溯
- [ ] 是否有关键事件（swap 事件）记录 `amountIn/amountOut` 便于链上分析？
- [ ] revert 是否用自定义错误（更省 gas、更清晰）？

---

## 10. 运行命令（示例）
```bash
cd labs/foundry-labs
forge test --match-contract D24_ -vvv
```

---

## 11. 今日结论
- 没有 `minOut` 的 swap 在 MEV 场景下很危险：用户可能在“极差价格”下仍然成交。
- 修复的核心是：**把“可接受价格”变成硬约束**（`minOut`）并限制执行时间窗口（`deadline`）。
- 测试上要学会区分：
  - 技术失败（revert） vs 业务失败（成交但亏得离谱）
