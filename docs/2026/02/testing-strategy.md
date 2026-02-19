# Testing Strategy — Vulnerability Regression Lab (D15–D26)

tags: [foundry, solidity, security, testing, regression, fuzz]

> 本仓库是“合约漏洞复现 + 修复验证”的回归实验库。目标不是写 demo，而是沉淀一套可持续扩展、可 CI 回归的安全测试资产。
>
> 覆盖范围：D15–D26（两周），包含重入、权限、初始化、ERC20 approve 竞态、整数精度/舍入、预言机操纵、闪电贷、滑点保护、Gas DoS、时间依赖等典型高危场景。

---

## 1. 目标与范围

### 1.1 目标（What we guarantee）
对每个漏洞主题（Day / Topic）保证：
1) ✅ **Exploit 可复现**：至少 1 条测试证明漏洞在 Vuln 合约上可被利用（资产变化/状态异常/权限越权等）。
2) ✅ **Fix 可验证**：至少 1 条测试证明同样的攻击对 Fixed 合约失效（revert 或无收益/无状态破坏）。
3) ✅ **回归可持续**：保留“最小复现”用例，后续新增内容不应破坏既有行为（Regression）。

### 1.2 覆盖漏洞主题（D15–D26）
> 主题命名按仓库统一规范：`Dxx_<Topic>Vuln.sol` / `Dxx_<Topic>Fixed.sol` + `test/vulns/Dxx_<Topic>.t.sol`

- **D15 Reentrancy（重入）**：最小银行（攻击合约 + 修复回归）
- **D16 Access Control / Role（权限缺陷）**：缺 onlyOwner/role（未授权调用成功 + 修复回归）
- **D17 Initialization（初始化漏洞）**：init 可重复调用（攻击 + initializer 修复）
- **D18 ERC20 Approve Race（approve 竞态）**：先改额度被夹（安全改法：先置 0 / increaseAllowance）
- **D19 Precision / Rounding（整数精度/舍入）**：share/fee 舍入套利（小额/大额边界）
- **D20 Docs & Index（工程化整理）**：统一 docs 模板 + README “漏洞索引表”
- **D21 Refactor & Green（机动补漏）**：补漏/重构，确保全量回归跑绿
- **D22 Oracle Manipulation（预言机操纵）**：可控价格源导致借贷/兑换异常（操纵前后资产变化）
- **D23 Flash Loan + Price Impact（闪电贷影响）**：同一交易内改变价格/余额导致套利（mock flash loan）
- **D24 Slippage Protection（滑点缺失）**：swap 无 minOut（“任意价格都成交”失败测试 + 修复）
- **D25 Gas Griefing DoS（DoS/大循环）**：数组增长导致关键函数不可用（阈值后必失败 + 修复）
- **D26 Timestamp Dependence（时间依赖）**：block.timestamp 边界（warp 测试“可操控窗口”）

> 注：D20、D21 更偏“工程化/质量门禁”，依然纳入策略：把每个 Day 的样例变成可维护的回归资产。

---

## 2. 测试分层（Test Pyramid for Security Labs）

### 2.1 Unit Regression（必做）
**每个漏洞 Day 至少两条核心测试：**
- `test_vuln_exploit_succeeds()`：攻击成功（证明漏洞存在）
- `test_fix_blocks_exploit()`：修复阻断（证明修复有效）

Unit 测试强调：
- 确定性（deterministic）
- 最小化依赖（尽量不依赖随机性）
- 因果链清晰（trace 友好，便于审计复盘）

### 2.2 Boundary & Negative（强烈建议）
为每个主题补“边界/反例”，提升覆盖与可解释性：
- **时间边界**：deadline/活动开始结束/卡边界（D26、D24）
- **数值边界**：0、1、最小单位、极大值（D19、D18）
- **gas 边界**：限制 gas 下是否可推进（D25）
- **权限边界**：admin/role/未授权账户行为对比（D16、D17）

### 2.3 Fuzz & Invariant（可选但加分）
用于捕捉“未想到的组合”与长期回归：
- **Fuzz**：对关键参数做 `bound/assume` 收敛后随机覆盖
- **Invariant**：定义系统不变量（余额守恒、总供给一致、权限不可越权等）
- 对经济类（D19、D22–D24），优先写：**资产不应凭空增加、可获利路径必须被阻断**。

---

## 3. 断言体系（Assertion Framework）

> 安全测试要“可证明”。断言必须落到链上状态、事件或错误码上。

### 3.1 状态断言（State）
常用断言点：
- `balanceOf(user/protocol/attacker)`
- `totalSupply / totalAssets / reserves / debt`
- shares 与 assets 的关系（vault/份额系统：D19）
- 关键配置是否被篡改（owner/admin/role/oracle/treasury）

推荐写法：
- 攻击前 `snapshot` → 攻击后断言
- Fix 场景断言“状态不变”或“收益为 0”

### 3.2 事件断言（Events）
用于证明关键路径发生过：
- `vm.expectEmit()` 校验事件参数（Transfer/Approval/Deposit/Withdraw 等）
- D18 approve 竞态：尤其建议校验 Approval 事件与 allowance 变化是否符合预期

### 3.3 Revert 断言（Errors）
推荐用 selector 精确断言（比只写 `expectRevert()` 更稳）：
- `vm.expectRevert(abi.encodeWithSelector(X.selector, ...))`

典型场景：
- 未授权访问（Ownable/AccessControl 错误）
- 过期交易（Expired/Deadline）
- 重入保护（ReentrancyGuard）
- 重复初始化（InvalidInitialization / AlreadyInitialized）

### 3.4 经济断言（Economics）
对 D19、D22–D24 这类经济攻击，必须包含：
- attacker profit：`attackerBalAfter - attackerBalBefore`
- protocol loss：`protocolBalBefore - protocolBalAfter`
- 关键价格/储备/份额变动（spot price / reserves / shares）

---

## 4. Foundry Cheatcodes 使用策略（可测性基础设施）

### 4.1 身份与权限
- `vm.prank(addr)`：单次调用模拟 msg.sender
- `vm.startPrank(addr) ... vm.stopPrank()`：连续调用同一身份（exploit 链条更清晰）

### 4.2 时间控制（D24/D26）
- `vm.warp(ts)`：测试 deadline、活动开始/结束、卡边界窗口
- 边界用例：`t-1 / t / t+1`（“最后一秒是否能成功/价格差距巨大”类问题）

### 4.3 资金与初始状态
- `deal(token, addr, amount)` 或合约 `mint` 方式准备资产
- 对 D23 flash loan：用 mock flash loan（同一 tx 内借出-操纵-归还）保证确定性

### 4.4 Fuzz 收敛
- `bound(x, min, max)`：把随机值压到合理区间
- `vm.assume(cond)`：过滤不合理输入（不要过度 assume 导致覆盖不足）

### 4.5 Gas/DoS 场景（D25）
- `target.call{gas: gasCap}(...);`：限制 gas 复现 OOG / 推进失败
- Fixed 方案测试应证明：**在 gasCap 下仍可分批推进并最终完成**

---

## 5. 每类漏洞的测试要点（D15–D26 Checklist）

### 5.1 D15 — Reentrancy（最小银行）
**Vuln 测试：**
- 部署 `ReentrancyAttacker`，在 `receive/fallback` 里 reenter `withdraw`
- 断言：attacker 多取出资产 / bank 余额被抽干（profit & loss）

**Fix 测试：**
- CEI（先更新余额再外部转账）或 `ReentrancyGuard`
- 断言：攻击 revert 或收益为 0；bank 关键状态不破坏

---

### 5.2 D16 — Access Control / Role（缺 onlyOwner/role）
**Vuln 测试：**
- 未授权账户调用关键函数成功（setTreasury / grantRole / mint 等）
- 断言：配置被篡改 / 资产被铸造 / 权限越权

**Fix 测试：**
- `onlyOwner` 或 `AccessControl` 正确约束
- 断言：未授权调用精确 revert（selector）；授权账户可成功

---

### 5.3 D17 — Initialization（init 可重复调用）
**Vuln 测试：**
- 反复 `initialize` 夺取 admin/owner 或重置关键参数
- 断言：admin 被改写 / 权限提升 / 配置被覆盖

**Fix 测试：**
- `initializer` onlyOnce 或 `reinitializer` 策略（按你的实现）
- 断言：重复初始化 revert；状态不可被二次篡改

---

### 5.4 D18 — ERC20 approve Race（approve 竞态）
**Vuln 测试（演示“先改额度被夹”）：**
- 初始 allowance = A
- owner 想把 allowance 改成 B（直接 `approve(B)`）
- attacker 在同一时间窗口抢跑 `transferFrom` 花掉 A，再让 approve 生效，最终可额外使用 B（或造成超出预期的总花费）
- 断言：总花费 > 预期（owner 认为只会让额度变成 B）

**Fix 测试（安全改法）：**
- 方案 1：先 `approve(0)` 再 `approve(B)`
- 方案 2：使用 `increaseAllowance/decreaseAllowance`
- 断言：不存在“花掉旧额度 + 再拿到新额度”的超额窗口（或流程被强制拆分降低风险）

> 备注：D18 重点在“竞态窗口”与“用户预期差异”。测试要尽量确定性，必要时用两步交易模拟抢跑顺序。

---

### 5.5 D19 — Precision / Rounding（整数精度/舍入套利）
**Vuln 测试：**
- share/fee 舍入不一致（向下取整/向上取整混用）导致可循环套利
- 写 **边界用例**：
  - 小额（1、2、几 wei）反复循环（累计多拿 1 wei）
  - 大额（接近池子规模）观察误差放大/不合理收益
- 断言：attacker profit 累计增长；系统资产/份额关系被破坏

**Fix 测试：**
- 统一舍入方向；对关键计算加校验（例如最小份额/最小资产、dust 处理）
- 断言：循环套利收益为 0 或无法达成；不变量（资产≈份额映射）稳定

---

### 5.6 D20 — Docs & Index（工程化整理）
**目标不是新增漏洞，而是提高回归资产可维护性：**
- 统一命名、统一文档模板、README “漏洞索引表”
- 断言方式：仓库层面的“质量门禁”
  - 每个 Day 必须有 Vuln/Fixed/Tests/Doc/Index 入口
  - `forge test` 全量回归可跑

---

### 5.7 D21 — Refactor & Green（补漏/重构）
**回归稳定性优先：**
- 修复 flaky / 依赖顺序的测试
- 提升可读性：拆分 setup、复用 helper、统一错误断言
- 目标：本周 5 个漏洞全部“跑绿”，并保留最小复现测试

---

### 5.8 D22 — Oracle Manipulation（可控价格源）
**Vuln 测试：**
- 攻击者操纵价格源（或调用 update）导致借贷/兑换异常
- 断言：操纵前后资产变化（profit/loss）与关键限制被突破

**Fix 测试：**
- 引入更稳健价格（TWAP/多源/上下限/延迟更新，按你的简化实现即可）
- 断言：操纵不足以突破限制，交易被拒绝或收益为 0

---

### 5.9 D23 — Flash Loan + Price Impact（同 tx 内操纵）
**Vuln 测试：**
- mock flash loan：借出→操纵 AMM reserves/价格→套利/借贷→归还
- 断言：单笔交易内出现可获利路径（attacker profit > 0）

**Fix 测试：**
- 关键逻辑不依赖即时 spot 值；或加入操纵防护窗口/限速/上限
- 断言：同样 tx 内无法获得异常收益（profit=0 或 revert）

---

### 5.10 D24 — Slippage Protection（缺 minOut）
**Vuln 测试：**
- swap 不校验 minOut → “任意价格都成交”
- 断言：在极差价格下仍成交（用户 out 远低于合理值）

**Fix 测试：**
- 校验 `minOut` + （可选）`deadline`
- 断言：`out < minOut` 时精确 revert；满足时成功且输出合理

---

### 5.11 D25 — Gas Griefing DoS（大循环/数组增长）
**Vuln 测试：**
- 数组增长导致 distribute/settle 等关键函数 OOG
- 断言：达到阈值后在 gasCap 下必失败（不可用）

**Fix 测试：**
- 分页处理 / pull-based claim / checkpoint
- 断言：在 gasCap 下可分批推进并最终完成（进度可持续）

---

### 5.12 D26 — Timestamp Dependence（矿工可操控窗口）
**Vuln 测试：**
- 关键逻辑依赖 `block.timestamp` 边界
- 使用 `vm.warp` 写 `t-1 / t / t+1` 边界用例
- 断言：边界导致“是否成功/价格差距巨大/可套利”的不一致

**Fix 测试：**
- 容忍窗口/时间范围检查/更稳健的时间设计（按场景）
- 断言：边界不会造成可利用收益或不公平状态变化

---

## 6. 新增漏洞 Day 的准入标准（Definition of Done）

新增一个 Day 必须满足：
- ✅ 合约成对：`Vuln` + `Fixed`
- ✅ 测试至少 2 条：exploit succeeds + fix blocks exploit
- ✅ 文档齐全：Threat Model / Exploit Steps / Fix / Tests / Audit Checklist / Run Command
- ✅ INDEX 更新：docs 入口可导航
- ✅ 全量回归通过：`forge test` 绿

---

## 7. 运行方式（Runbook）

### 7.1 按 Day/Topic 跑
```bash
cd labs/foundry-labs
forge test --match-path test/vulns/D23_*.t.sol -vvv
```

### 7.2 按合约名跑
```bash
forge test --match-contract D25_GasGrief_Test -vvv
```

### 7.3 按单个测试函数跑
```bash
forge test --match-test test_fix_deadlineExpired_reverts -vvv
```

### 7.4 全量回归
```bash
forge test
```

---

## 8. CI 建议（可选）
- 最小 CI：每次 PR 跑 `forge test`
- 可选增强：
  - coverage 产物（lcov/genhtml）作为 artifact
  - 对关键 Day（D22–D26）保留 trace 失败日志，方便定位

---

## 9. 审计视角：仓库级总纲 Checklist
- 权限：关键函数是否受控？角色是否可被错误授予/撤销？
- 外部调用：是否违反 CEI？是否可能重入？
- 时间：是否依赖 `block.timestamp` 边界？是否有 deadline？
- 价格：是否使用 spot price？是否易被操纵？是否缺少防操纵窗口？
- 交易保护：是否校验 `minOut`？是否可被夹击/滑点吞噬？
- DoS：是否存在无界循环/遍历？是否可分页/可推进？
- 舍入：是否存在向上/向下取整不一致导致的套利路径？
- 错误处理：revert 是否精确、可测试、可回归？
