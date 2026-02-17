# 2026-02-17 - D23 Flash Loan 影响：同一交易内操纵价格/余额导致可套利（Route A + Route B）

tags: [flash-loan, defi, oracle, amm, spot-price, vault, donation, lending, foundry, security]

> 本日目标：理解 Flash Loan 的“原子性放大”与两类典型风险：  
> - **Route A（Donation/余额操纵）**：用外部转账改变 vault 余额 → 扭曲 share 定价  
> - **Route B（Spot Oracle 价格操纵）**：用 flash loan 大额 swap 推高/压低 AMM 现价 → 借贷/兑换按错误价格放款

---

## 1. Flash Loan 是什么（用一句话抓住本质）
Flash Loan（闪电贷）= **同一笔交易内借出巨额资金**，并要求在交易结束前 **归还本金 + fee**。  
若未归还，出借方在交易末尾 `revert`，整笔交易回滚（借出也视为未发生）。

关键点：
- 不靠抵押，靠 **原子性**（atomicity）
- 攻击价值：把“需要长期资金才能做到的操纵”变成“只需 gas + fee 的一次交易”

---

## 2. Route A：Donation/余额操纵（Vault share 定价风险）

### 2.1 漏洞靶子：`VulnVaultDonation`
核心漏洞点（审计关键词：Donation / Inflation / Share Price Manipulation）：
- `totalAssets()` 直接用 `asset.balanceOf(address(this))`
- share 定价依赖 `totalAssets()` 与 `totalSupply`
- 任何人都能 `asset.transfer(vault, X)`（不走 deposit）改变 vault 余额

> 结论：**把“可被外部强转影响的余额”当作关键定价输入**，属于高危审计点。

### 2.2 为什么 Route A 不一定能 flash-loan 闭环盈利？
你在实测中看到：把借来的大额资产 donation 给 vault 后，攻击者只有极小 shares 占比，赎回得到的资产远小于本金，导致还不上 `amount + fee`，交易必 revert。

这也是很有价值的审计认知：
- **“可操纵”≠“必能闭环盈利”**  
- 但依然是漏洞：如果协议的另一个路径（例如 mint/share 计算错误、舍入方向错误、错误快照）允许攻击者拿回更多资产，就可能形成闭环。

### 2.3 Route A 的学习产物（保留代码）
- 合约：`labs/foundry-labs/src/vulns/VulnVaultDonation.sol`
- 攻击：`labs/foundry-labs/src/vulns/AttackDonation.sol`
- 测试：`labs/foundry-labs/test/vulns/D23_FlashLoanDonation.t.sol`

---

## 3. Route B：Spot Oracle 价格操纵（最典型、最贴近真实 DeFi）

### 3.1 系统组件
- `SimpleAMM`（x*y=k）：提供 `swapExactIn` + `spotPrice0Per1()`（USD/ETH）
- `SpotOracleLending`（漏洞借贷）：
  - 抵押 ETH
  - 用 AMM **spot price** 计算抵押价值
  - 按 LTV 放出 USD
- `FlashLenderMock`：借出 USD 并回调 `onFlashLoan`
- `AttackSpotOracle`：flash loan → swap 拉价 → 抵押 → 借出 → 还款 → 留利润

### 3.2 Route B 攻击流程（同一 tx）
1) `flashLoan(USD, L)`  
2) 回调中大额 `swap USD -> ETH`：  
   - `reserveUSD` ↑、`reserveETH` ↓  
   - `spotPrice = reserveUSD/reserveETH` **瞬时变大（ETH 被抬价）**
3) 将得到的 ETH 抵押进借贷协议  
4) 借贷协议按被操纵的 spot price 计算抵押价值 → 放出更多 USD  
5) 用借到的 USD 归还 `L + fee`，剩余 USD 为利润  
6) 交易结束：协议 USD 流动性下降（被抽走），留下坏账风险
- 合约： `labs/foundry-labs/src/vulns/SpotOracleLending.sol`
        `labs/foundry-labs/src/vulns/SimpleAMM.sol`
- 攻击： `labs/foundry-labs/src/vulns/AttackSpotOracle.sol`
- 测试： `labs/foundry-labs/src/vulns/D23_FlashLoanSpotOracle.t.sol`

### 3.3 你遇到的失败原因（ExceedsBorrowLimit）
报错示例：
- want=400,000 USD
- limit≈373,875 USD

原因：在 LTV=50% 条件下，swap 后得到的 ETH 抵押价值不足以支撑借到 400k。

更重要的是：即便把 `borrowUsd` 调低到 ≤ limit，也会因为你需要还 `500,250`（本金+fee），借得不够依然无法还款。

### 3.4 让 Demo “可跑闭环”的最小调整（学习用）
为了让 Route B **演示“操纵→兑现→还款→利润”闭环**，建议采用更“放水”的参数（学习 Demo 合理）：

- 将 LTV 从 50% 提高到 90%：
  ```solidity
  lending = new SpotOracleLending(usd, eth, amm, 9000); // 90% LTV
  ```
- 选择能覆盖还款的 borrow：
  - flashUsd=500,000
  - fee=0.05% → 250
  - 需还款=500,250
  - 示例：`borrowUsd=520,000`（同时 ≤ 限额且 ≤ 协议流动性）

这样：`borrowUsd` 可以覆盖还款并留下利润。

> 真实协议通常不会设置这么高的 LTV；现实攻击更常见的是：  
> - 不把全部 flashUsd 都 swap（保留一部分用于还本金）  
> - 或借完后再反向 swap 回收 USD  
> 本日先以“最小可跑闭环”理解机制为主。

### 3.5 运行命令（Route B）
```bash
cd labs/foundry-labs
forge test --match-contract D23_FlashLoanSpotOracle_Test -vvv
```

---

## 4. 涉及到的知识点清单（D23）
### Flash Loan
- 原子性回滚：还不上就 revert，整个交易回滚
- 回调模型：lender → borrower.onFlashLoan
- `msg.sender` 逐层变化：跨合约 external call 会改变 `msg.sender`
- 常见防御：回调权限校验（only lender）、重入防护等

### AMM（x*y=k）
- 常数乘积曲线：交易后保持（近似）不变量
- spot price：储备比 `reserve0/reserve1`（曲线斜率/边际价格）
- 滑点：大额交易推动储备变化导致成交价变差
- 手续费：有效输入 `amountInWithFee`，费用留在池子里（k 增大）

### Oracle
- spot price 不适合做 oracle：可被同 tx 操纵
- 更安全替代：TWAP、外部预言机（Chainlink）、多源聚合、偏离限制

### 借贷基本概念
- 抵押价值（USD 计价）
- LTV（Loan-to-Value）
- 借款上限：`valueUsd * ltvBps / 10_000`

---

## 5. 审计视角 Checklist（Route A + Route B）
### A. 是否存在“同一交易内可操纵”的定价输入
- [ ] 是否使用 `token.balanceOf(protocol)` 作为 `totalAssets()` / 关键定价？
- [ ] 是否使用 AMM **spot price** 作为 oracle？
- [ ] 关键定价变量是否能被外部转账/强转（donation/forced transfer）影响？
- [ ] 是否存在“先操纵价格/余额，再执行关键借贷/赎回/兑换”的路径？

### B. 是否可形成“原子闭环”
- [ ] 是否存在 flash loan 回调中“操纵 → 兑现 → 还款”的完整路径？
- [ ] 兑现路径是否直接把资产转出（borrow/swap/redeem/liquidate）？
- [ ] 还款来源是什么？（被薅协议的资金 / 反向 swap / 外部补贴）
- [ ] fee/滑点/限额 是否会阻断闭环？（很多 PoC 失败就在这里）

### C. 约束与保护机制
- [ ] 是否有滑点保护（minOut / maxImpact）？
- [ ] 是否有价格偏离检查（max deviation / TWAP window）？
- [ ] 是否有同区块限制/冷却时间（anti-flash-loan）？
- [ ] 是否有多源价格校验（oracle aggregation）？

### D. 资产流向与断言（测试应体现）
- [ ] 攻击者利润 `profit > 0`
- [ ] 协议资产减少（如 lending 的 USD liquidity 下降）
- [ ] 价格/储备被操纵（spot price before/after）
- [ ] 交易能成功完成（闪电贷还款校验通过）

---

## 6. 建议的 commit message
- `feat(d23): add flash-loan demos (donation vault + spot oracle lending) and audit notes`
