# D48｜DEX 测试文档：风险点 → 用例 → 断言指标（Checklist & Playbook）

> **建议放置目录：** `docs/checklists/dex-testing.md`  
> 说明：这是“可复用的测试清单/方法论文档”，适合沉淀在 `checklists`，并在每次 DEX/AMM 相关任务（D43~）里引用。

---

## 0. 适用范围与目标

**适用：**
- 常数乘积 AMM（x*y=k）/ 变体（带 fee）
- 路由器（Router）/ 多跳 swap
- LP 增加/移除流动性（mint/burn）
- 价格预言机：spot / TWAP（如用 AMM 价格）
- 与借贷、清算、稳定币池等集成场景（可选扩展）

**目标：**
- 用“风险点 → 用例 → 断言指标”把 DEX 的关键安全与正确性覆盖起来
- 让测试从“能跑”升级到“能证明性质”（properties / invariants）
- 提供可直接复制的断言指标与常见失败信号

---

## 1. 测试输入与观测（统一口径）

### 1.1 测试角色（推荐最少集合）
- `lp`：提供流动性
- `trader`：正常交易者
- `attacker`：对抗者（夹子/操纵/重入/闪电贷）
- `feeTo/treasury`：协议费接收者（若存在）

### 1.2 统一观测指标（每类用例尽量落到这些断言）
- **池子层**
  - `reserve0/reserve1`（若有）
  - 实际余额 `balanceOf(pool)` 与 `reserve` 一致性（若实现分离）
  - `k = reserve0 * reserve1`（或你实现的 invariant）
  - fee 累积：LP fee / protocol fee 的去向与数额
- **用户层**
  - 交易前后余额变化：`Δin` / `Δout` / `Δfee`
  - LP token：`totalSupply` 与 `balanceOf(lp)`
- **价格层**
  - spot price：`p = y/x`（或 `x/y`）
  - TWAP：时间窗口平均价（若有）
- **安全层**
  - 预期 revert（错误类型/自定义 error）
  - 事件（Swap/Mint/Burn/Sync）参数一致性
  - 不变量（invariant）是否被破坏

---

## 2. 核心风险点 → 用例 → 断言指标

> 下面每一条都按固定三段：**风险点**（为什么危险）→ **用例**（怎么测）→ **断言指标**（怎么判定）。  
> 你可以从“最小 AMM”开始逐条落地，后续再覆盖 Router、多跳、闪电贷等扩展。

---

### R1｜滑点保护缺失（minOut / maxIn）

**风险点**
- 没有 `minOut`（或 `maxIn`）时，价格在交易前被操纵会导致成交极差，用户被“夹”或被恶意路由吃差价。

**用例**
1. trader 准备 swap（预期换出较多）  
2. attacker 先用一笔交易改变池子价格（制造滑点）  
3. trader 执行 swap（如果没有 minOut，会以极差价格成交）  
4. 修复版：增加 `minOut`，应 revert

**断言指标**
- 漏洞版：`actualOut << expectedOut`（明显变差）
- 修复版：`expectRevert(SlippageExceeded / TooLittleReceived)`
- 价格断言：`spotPrice_before != spotPrice_after_attack`
- 资金断言：trader 余额变化与事件一致

---

### R2｜deadline 缺失或无效（过期交易仍可执行）

**风险点**
- 用户签名或提交的交易本应在一定时间内有效；若不校验 `deadline`，攻击者可延后执行，在价格变坏时成交。

**用例**
1. 设定 `deadline = now + 60`  
2. `warp(now + 61)` 后执行 swap  
3. 修复版应 revert

**断言指标**
- `expectRevert(Expired / DeadlinePassed)`
- 不应有任何状态变化：reserve、余额、事件（可选：`vm.recordLogs` 验证无 Swap 事件）

---

### R3｜k 不变量被破坏（公式/更新顺序/舍入错误）

**风险点**
- swap 公式写错、更新 reserve 顺序错、fee 处理错、整数舍入不当，都可能导致 `k` 下降（可被套利/掏空）。

**用例**
- invariant fuzz：随机多次 swap（0→1 / 1→0）  
- 重点覆盖：小额、边界额、接近打空的一侧

**断言指标**
- fee 留池子模型：`kAfter + tol >= kBefore`
- 无 fee 模型：`kAfter` 不应“显著”低于 `kBefore`（容忍 rounding）
- 额外：`reserve0 > 0 && reserve1 > 0`（不被打到 0）

---

### R4｜reserve 与实际余额不一致（donation / sync 问题）

**风险点**
- 若池子使用 `reserve` 记账，但允许外部直接 `transfer` token 到池子，可能导致“余额变了 reserve 没变”，造成报价异常或可套利。

**用例**
1. 正常初始化后，外部账户直接向 pool `transfer` token（donation）  
2. 不调用 sync 的情况下执行 swap / mint  
3. 看是否出现异常出价或 k 规则被破坏  
4. 若实现有 `sync()`，验证 sync 后行为一致

**断言指标**
- `balanceOf(pool) != reserve` 时应有明确策略：
  - 允许并可通过 `sync()` 修正，且 swap 不应让攻击者赚走 donation 的不合理份额
  - 或禁止（如校验）并 revert
- 事件 `Sync(reserve0,reserve1)` 参数应与真实余额一致（若有）

---

### R5｜手续费（LP fee / protocol fee）分配错误

**风险点**
- fee 计算位置错（input/output）、精度溢出/截断、或 protocol fee 抽走逻辑错，会导致 LP 被少分/多分，或 k 下降。

**用例**
1. 设置固定 fee（如 0.3%）  
2. 执行一系列 swap（包含不同方向/不同大小）  
3. 验证 fee 留存与分配去向（LP 或 treasury）

**断言指标**
- fee 留池子：swap 后池子某侧余额增长应体现 fee
- protocol fee：`treasuryBalance` 按规则增长（且与事件一致）
- 若你实现了“开关”：开/关 protocol fee 行为一致可预测

---

### R6｜LP 增加/移除流动性：份额计算/舍入/边界

**风险点**
- LP token mint/burn 计算错误会导致份额被稀释或被薅羊毛；最常见是舍入与最小流动性处理。

**用例**
1. 初始 LP：存入 (x,y)，获得 LP token  
2. 第二个 LP：按比例存入，应得到可预期份额  
3. 移除流动性：按份额取回，应满足近似比例（容忍 rounding）  
4. 边界：极小存入、只存一边（若允许）应 revert 或按策略处理

**断言指标**
- `lpOut` 与比例接近：`lpOut ≈ totalSupply * min(dx/x, dy/y)`（视实现）
- `burn` 后：`Δtoken0/Δtoken1` 与份额一致
- `totalSupply` 单调性与不为 0（视最小流动性机制）

---

### R7｜权限/配置错误（fee 参数、暂停、白名单、救援等）

**风险点**
- feeBps 可被任意人改、路由器地址可被替换、暂停开关缺失都会导致资金风险。

**用例**
- attacker 尝试修改关键参数 / 调用受限函数
- admin 正常修改后，行为符合预期

**断言指标**
- `expectRevert(Unauthorized / onlyOwner / AccessControl...)`
- 参数修改后：对应模块行为改变且可预测（例如 fee 生效）

---

### R8｜重入（swap/mint/burn 与回调）

**风险点**
- swap 中如果在更新状态前对外部合约转账/回调，可能被重入改变 reserve，造成盗取。

**用例**
1. 攻击合约在 `tokenReceived`/`fallback` 中重入 swap/mint/burn  
2. 漏洞版可能被抽走余额  
3. 修复版（CEI/ReentrancyGuard）应 revert 或无效

**断言指标**
- 漏洞版：attacker 资产净增且超过合理范围
- 修复版：`expectRevert(Reentrancy / Locked)` 或余额不变
- 不变量：`k`、reserve 不被异常破坏

---

### R9｜价格操纵（小池子/低流动性）与借贷/预言机联动

**风险点**
- 用 spot price 作为预言机时，攻击者可在小池里用少量资金拉价/砸价，扩大借贷额度、套走资产（常见 D22/D45 场景）。

**用例**
1. 构造低流动性池  
2. attacker swap 拉价/砸价  
3. 借贷合约读取 spot price，允许更高 borrow  
4. attacker 借出资产并回到原价（或通过闪电贷）

**断言指标**
- 价格断言：`spotPrice` 被显著偏移
- 协议资产断言：lending 的可借额度异常提升
- 资金断言：attacker 净收益 > 0 且协议净损失

---

### R10｜TWAP/时间窗实现错误（时间依赖/边界）

**风险点**
- TWAP 如果窗口更新、累计价格、时间间隔处理错，可能被短时操纵或出现除零/溢出，导致错误报价。

**用例**
1. 正常时间推进，多次更新累计值  
2. 进行短时操纵并立刻恢复  
3. 验证 spot 被操纵但 TWAP 不应大幅跟随（在窗口足够长时）

**断言指标**
- `twapPrice` 相对稳定（阈值）
- 边界：`timeElapsed=0` 时应 revert 或不更新（按实现）
- 累计量单调性（若用累加器）

---

## 3. Invariant 套件（推荐最少 3 条）

> 适合放在 `test/invariants/` 或 `test/vulns/` 的 invariant 合约里。

1) **k 不下降（fee 留池子）**  
   - `kAfter + tol >= kBefore`
2) **储备非零且不溢出**  
   - `reserve0 > 0 && reserve1 > 0`  
   - 若用 `uint112`：确保不会截断（可用 bound 控输入）
3) **池子资产不被凭空转移**（按你的实现定义）  
   - 例如：除 swap/mint/burn 外，不应出现无授权的资产流出

---

## 4. 用例模板（推荐你后续 D49+ 继续沿用）

### 4.1 用例写法模板（你可以复制粘贴）
- **Given**：初始流动性、角色资金、参数（fee、deadline）
- **When**：攻击/操纵发生（前置交易）
- **Then**：断言指标（余额、价格、k、事件、revert）

### 4.2 断言指标模板（推荐最低集合）
- `assertEq`：余额、totalSupply、reserve
- `assertGt/Ge`：收益、k、价格偏移幅度
- `vm.expectRevert`：错误类型严格匹配
- `vm.recordLogs`：事件参数一致性（可选）

---

## 5. 快速落地清单（你今天能立刻做的）

- [ ] 把你 D43 的最小 AMM 接入 fee-on-input（或确认已有）
- [ ] 把 D44 的 `minOut/deadline` 作为 Router/AMM 的安全参数
- [ ] 在 `test/invariants/` 新增：k 不下降 invariant（D47）
- [ ] 新增 D48 文档并在 `docs/2026/02/INDEX.md` 加索引

---

## 6. 附：目录建议

- 方法论文档（长期复用）：`docs/checklists/dex-testing.md` ✅（推荐）
- 每日学习沉淀（可选）：`docs/2026/02/2026-02-22-D48-DEX-testing-checklist.md`
- 测试代码：
  - 单元/漏洞回归：`test/vulns/`
  - 不变量：`test/invariants/`（若你想拆分更清晰）

