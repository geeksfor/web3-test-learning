# D44｜滑点 / 最小输出（minOut）：没有 minOut 的风险测试（先写失败用例）

日期：2026-02-21  
主题：AMM/DEX 交易的 **滑点保护**（minOut）与可复现风险测试（sandwich / 插队导致成交变差）

---

## 1. 任务目标（你今天要完成什么）

- 搭一个最小 `x*y=k` AMM（或在已有 AMM 示例上改）
- 写一个**漏洞版本**：`swapExactIn()` **没有** `minOut`
- 写一个**失败用例（红测）**：攻击者插队改变价格后，用户成交显著变差，但交易仍会执行
- 写一个**修复版本**：`swapExactIn(..., minOut, deadline, ...)`；当输出 < minOut 时 `revert`
- 写一个**回归测试（绿测）**：同样场景下应当 `revert`，从而阻断 sandwich/滑点风险

---

## 2. 知识点与原理（通俗解释）

### 2.1 什么是滑点（Slippage）
在 AMM 里价格由池子储备决定，交易执行时输出取决于“当时的 reserve”。

你在发交易时看到的报价 **≠** 上链执行时的实际输出，因为：
- 同一个区块内可能有人在你之前先做交易（插队/MEV）
- 你进入 mempool 后等待出块期间价格发生变化
- 池子流动性较小，你的单子本身会推动价格（价格冲击）

于是你实际拿到的 `amountOut` 可能比预期少，这就是滑点。

### 2.2 为什么必须要 minOut（最小输出）
`minOut` 的本质是一句人话：

> “我能接受最差拿到多少；再少我宁愿失败也不成交。”

没有 `minOut` 的风险：
1. **Sandwich（三明治）攻击**：攻击者前腿先交易把价格打歪 → 你拿到更少；后腿反向交易套利。
2. **价格波动**：你以为能拿到 100，实际只拿到 60 也会成交。
3. **低流动性/大额单**：输出极差仍成交，用户体验与资金安全风险都很高。

### 2.3 minOut 和 deadline 的区别
- `minOut`：限制“最差成交价/最少拿到多少”
- `deadline`：限制“这笔单子多久内有效”，防止交易挂太久导致条件变化（尤其是被延迟打包）

---

## 3. 通过本案例能学到什么

- ✅ 如何把“安全风险”写成**可复现的测试**（红测证明漏洞真实存在）
- ✅ 如何用 `minOut` 将风险转为**可验证的行为约束**（绿测证明修复有效）
- ✅ 理解 sandwich 的本质：不是玄学，是**缺失成交边界**导致的可被同区块交易影响
- ✅ 测试思路：不要只测“正常路径”，更要测“对抗路径”（adversarial）

---

## 4. 实现步骤（建议落地到你的仓库结构）

> 以 `labs/foundry-labs` 为例（路径可按你项目微调）

1) 新增合约（漏洞 + 修复）
- `src/vulns/D44_SlippageNoMinOut.sol`
- `src/fixes/D44_SlippageWithMinOut.sol`（建议包含 `deadline`）

2) 新增测试（红测 + 绿测）
- `test/vulns/D44_SlippageNoMinOut.t.sol`（**先写失败用例**：插队后输出变差仍成交）
- `test/fixes/D44_SlippageWithMinOut.t.sol`（回归：输出 < minOut 时必须 `revert`）

3) 运行命令
```bash
cd labs/foundry-labs
forge test --match-path test/vulns/D44_SlippageNoMinOut.t.sol -vvv
forge test --match-path test/fixes/D44_SlippageWithMinOut.t.sol -vvv
```

---

## 5. 关键代码（可直接复制）

> 说明：这里用最小 `x*y=k` 公式（无手续费），重点是复现“reserve 变化 → 输出变差”。

### 5.1 漏洞合约：没有 minOut（核心点）
`swapExactIn(tokenIn, amountIn, to)`  
- 直接根据当前 reserve 计算 `amountOut`
- 不做 `amountOut >= minOut` 检查 → 用户没有底线保护

**伪代码**：
```solidity
amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
transfer(outToken, to, amountOut);
updateReserves();
```

### 5.2 失败用例（红测）：插队导致输出变差仍成交
测试思路：
1. Alice 基于当前 reserve 先 `quoteOut()` 得到报价 `quotedOut`
2. attacker 先用大单交易改变 reserve（模拟插队/前腿）
3. Alice 再交易，实际输出 `outActual` 显著变少
4. 我们故意写一个“安全预期”：`outActual >= quotedOut * 99%`
5. 因为合约没有 minOut，这个断言会失败（证明漏洞）

**测试断言（失败点）**：
```solidity
assertGe(outActual, minAcceptable, "should have been protected by minOut, but it was not");
```

这类“红测”很适合在安全学习中使用：先证明风险可复现，再做修复。

### 5.3 修复合约：加入 minOut + deadline
修复点：
- `deadline`：`require(block.timestamp <= deadline)`
- `minOut`：`if (amountOut < minOut) revert Slippage(amountOut, minOut);`

**核心逻辑**：
```solidity
if (block.timestamp > deadline) revert Expired(nowTs, deadline);
amountOut = quoteOut(tokenIn, amountIn);
if (amountOut < minOut) revert Slippage(amountOut, minOut);
```

### 5.4 回归测试（绿测）：同样场景必须 revert
流程同红测，但 Alice 传入 `minOut = quotedOut * 99%`：
- attacker 插队后，Alice 的 `amountOut` 会 < `minOut`
- 预期：`expectRevert(Slippage.selector)`

---

## 6. 审计视角（Checklist）

**接口层**
- [ ] swap / redeem / mint 是否提供 `minOut`（或 `maxIn`）？
- [ ] `minOut` 是否真正生效（不是写死 0）？
- [ ] 是否提供 `deadline` 防止挂单？

**实现层**
- [ ] `amountOut` 的计算是否基于当前 reserve，并且在转账前/后正确更新？
- [ ] `Slippage` / `Expired` 是否用明确的 custom error，便于定位与前端处理？
- [ ] 是否存在 rounding（舍入）导致的边界问题（尤其是小额 swap）？

**测试层**
- [ ] 是否有 sandwich/插队的对抗测试（先改 reserve，再执行用户 swap）？
- [ ] 修复后是否有回归：输出低于 minOut 必须 revert？
- [ ] 低流动性/大额单的压力测试是否覆盖？

---

## 7. 今日产出清单（可贴到 PR 描述里）

- 漏洞：`swapExactIn()` 缺少 `minOut`，可导致用户在插队/MEV 下以极差价格成交
- 红测：复现插队后 `outActual << quotedOut`，断言失败证明风险
- 修复：加入 `minOut + deadline`，不满足则 revert
- 回归：同样插队场景下必然 revert，阻断风险

---

## 8. 建议的分支与提交信息

- 分支名：`d44-slippage-minout`
- Commit（综合一条）：
```
feat(d44): add no-minOut slippage vuln test and fix with minOut+deadline
```
