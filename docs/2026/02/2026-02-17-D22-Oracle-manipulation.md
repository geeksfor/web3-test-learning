# 2026-02-17 - D22 | Oracle 操纵（简化版）：可控价格源导致借贷异常（Foundry 实战）

tags: [oracle, defi, lending, amm, manipulation, foundry, solidity, security]

## 背景 / 目标
今天目标是用 **最小可跑闭环** 理解并复现「Oracle 被操纵」类风险：

- 构造一个 **可控价格源（MockOracle）**
- 借贷合约 **直接使用 oracle 价格** 计算可借额度（LTV）
- 在 Foundry 测试中写出关键断言：**“操纵前后资产变化”**（借到的资产数量对比 + 用公平价证明“借超了”）

> 这是一份教学版（简化版）实现，重点在“漏洞模式 + 断言”，不是生产可用借贷协议。

---

## 今日完成清单
- [x] 实现 `D22_MockOracle`（owner 可 `setPrice`）
- [x] 实现 `D22_VulnerableLending`（抵押 COL，借出 DEBT）
- [x] Foundry 用例：操纵前（正常价） vs 操纵后（抬价）借款对比
- [x] 额外用“公平价格”计算 `fairMaxBorrow`，证明操纵后借超
- [x] 补充审计视角 Checklist（如何在真实项目识别与缓解）

---

## 核心概念速记（面向“陌生感”快速消化）
### 1) Oracle 是什么？
- 合约需要“价格”等外部信息，但链本身不知道外界价格。
- **Oracle = 链上可被读取的价格接口（合约）**，价格通常由链下喂价系统写入，或由链上 DEX 统计计算（如 TWAP）。

### 2) 为什么 Oracle 会导致漏洞？
当协议把 **价格** 当成“真相”，并直接影响：
- 借贷额度（maxBorrow）
- 清算阈值（liquidation）
- 兑换输出（swap out）
就会出现：**价格被操纵 ⇒ 协议的资产计算被欺骗 ⇒ 资金被掏空 / 坏账**。

### 3) DEX / AMM 与 Oracle 的关系（关联理解）
- AMM（如 Uniswap V2）价格来自资金池储备比例（spot price）。
- **spot price 易被短时大额交易操纵**（闪电贷拉价）。
- 因此真实项目常使用 **TWAP / 多源聚合 / Chainlink 等成熟预言机**。

---

## 代码结构（建议路径）
- `src/vulns/D22_SimpleERC20.sol`：极简 ERC20（用于 COL/DEBT）
- `src/vulns/D22_MockOracle.sol`：可控价格源（1 COL 值多少 DEBT）
- `src/vulns/D22_VulnerableLending.sol`：简化借贷（抵押 COL 借 DEBT）
- `test/vulns/D22_OracleManipulation.t.sol`：操纵前后资产变化断言

---

## 漏洞模型（简化借贷）
### 资产与精度
- `COL`：抵押币（18 decimals）
- `DEBT`：借出币（18 decimals）
- `price`：`1 COL = price DEBT`，用 WAD（1e18）表示
- `LTV`：贷款价值比，例如 50% = `0.5e18`

### 关键公式
1) 抵押价值（按 DEBT 计价）：
- `valueInDebt = collateral * price / 1e18`

2) 可借上限：
- `maxBorrow = valueInDebt * LTV / 1e18`

### 漏洞点
借贷合约 **直接使用 `oracle.getPrice()` 的当前值** 计算 `maxBorrow`，没有：
- TWAP（抗短时操纵）
- 多源聚合 / 中位数过滤
- 偏差阈值、更新频率（heartbeat）、过期检查（stale price）
- 紧急暂停与风控兜底

因此：攻击者把 `price` 抬高 ⇒ 抵押看起来更值钱 ⇒ 借出更多 DEBT。

---

## Foundry 测试：操纵前后资产变化断言（最关键）
测试思路：
1. **正常价**：`1 COL = 100 DEBT`，LTV 50% ⇒ 存 1 COL 最多借 50 DEBT
2. **抬价后**：`1 COL = 1000 DEBT` ⇒ 同样存 1 COL 最多借 500 DEBT
3. 对比断言：
   - `maxManipulated > maxNormal`
   - 攻击者借到的 `DEBT` 增加量（balance delta）在操纵后显著更大
4. 用“公平价”证明借超：
   - 按公平价 100 计算 `fairMaxBorrow=50`
   - 断言 `debtAfterManipulated > fairMaxBorrow`

> 这组断言是安全测试最有“证据力”的部分：既证明“收益”，也证明“违反公平约束”。

---

## 运行命令
```bash
forge test --match-path test/vulns/D22_OracleManipulation.t.sol -vvv
```

---

## 审计视角 Checklist（D22）
下面这份清单可以直接作为审计/评审时的“问答式检查点”。

### A. Oracle 来源与信任边界
- [ ] Oracle 数据来自哪里？（Chainlink/自建/DEX spot/TWAP/混合）
- [ ] 是否单点？单一喂价者或单一池子是否能决定价格？
- [ ] Oracle 合约是否可升级？升级权限是否安全（多签/Timelock）？
- [ ] 喂价权限是谁？是否可能被盗用或绕过？

### B. 抗操纵能力
- [ ] 是否使用 **spot price** 直接定价？（高危）
- [ ] 若来自 DEX：是否使用 **TWAP**？窗口多长？是否足以抵御闪电贷？
- [ ] 是否有 **偏差阈值**（price deviation guard），超过阈值拒绝关键操作？
- [ ] 是否对低流动性资产做特殊处理（更严格的 LTV、更大窗口）？

### C. 数据新鲜度与异常处理
- [ ] 是否校验 **stale price（过期）**？（timestamp / roundId / heartbeat）
- [ ] 是否处理 oracle 暂停/失效？（fallback / pause / graceful degradation）
- [ ] 是否有异常报警与紧急开关（pause）？

### D. 经济参数与风控联动
- [ ] LTV / liquidation threshold 是否与 oracle 风险匹配？
- [ ] 是否有借贷上限、资产上限、单账户上限等“限流”？
- [ ] 是否有坏账处理机制（insurance、reserve、backstop）？

### E. 测试与验证（你今天写的就是这一类）
- [ ] 是否有“操纵前后资产变化”对照用例？
- [ ] 是否有 fuzz / invariant：例如「在合理价格区间内，协议总资产不应凭空减少」？
- [ ] 是否覆盖极端边界：价格为 0、暴涨、暴跌、长时间不更新？

---

## 今日输出（你可以复用的模板）
- 漏洞叙事：**同样抵押 → 抬价 → 借更多 → 用公平价证明借超**
- 断言套路：
  - `maxManipulated > maxNormal`
  - `balanceDeltaManipulated > balanceDeltaNormal`
  - `debtManipulated > fairMaxBorrow`

---

## 复盘：下一步怎么升级到“更真实”
（可选，后续 D23+ 或加餐）
- 把 MockOracle 改成 **DEX spot price oracle**（读池子储备比例）
- 增加一个“拉价 swap”步骤（甚至闪电贷模拟）
- 加清算逻辑展示：被操纵的价格会导致错误清算或坏账
