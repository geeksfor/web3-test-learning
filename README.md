# web3-test-learning

> Web3 / 智能合约测试开发 学习与作品集仓库（Foundry）

本仓库用于沉淀 **1–12 周学习计划**的代码与文档产出：从基础合约测试到安全回归、DeFi 场景、mainnet fork 回归与工程化 CI。
你可以把它当作「可一键运行的作品集」：**每周都有明确交付物（代码 + 测试 + 文档 + 可复现命令）**。

---

## 目录

- [目标与能力画像](#目标与能力画像)
- [快速开始](#快速开始)
- [推荐目录结构](#推荐目录结构)
- [12 周学习路线与交付物](#12-周学习路线与交付物)
  - [第 1–2 周：Foundry 基础与 ERC 测试](#第-12-周foundry-基础与-erc-测试)
  - [第 3–4 周：漏洞回归库 Top10+](#第-34-周漏洞回归库-top10)
  - [第 5–6 周：跨链与签名安全专项](#第-56-周跨链与签名安全专项)
  - [第 7–8 周：DeFi 场景化安全测试 + fork](#第-78-周defi-场景化安全测试--fork)
  - [第 9–10 周：工程化与工具链（CI/覆盖率/Slither/Echidna）](#第-910-周工程化与工具链ci覆盖率slitherechidna)
  - [第 11–12 周：作品集包装与面试准备](#第-1112-周作品集包装与面试准备)
- [测试策略（安全向）](#测试策略安全向)
- [CI 与质量门禁建议](#ci-与质量门禁建议)
- [FAQ](#faq)

---

## 目标与能力画像

目前合约知识储备：

- 用 **Foundry** 编写：单测（unit）/组合测试（integration）/模糊测试（fuzz）/不变量（invariant）/主网 fork 回归（fork）
- 能把常见风险沉淀为「**错误实现 → 利用 PoC → 修复 → 回归锁定**」的安全回归用例
- 对 DeFi 关键风险点有可测试能力：**Oracle 过期/跳变/操纵、滑点、清算边界、舍入套利、MEV 夹子简化**
- 工程化落地：GitLab CI / GitHub Actions，覆盖率产物与质量门禁（coverage/关键用例阻断），静态扫描（Slither）与不变量 fuzz（Echidna/Foundry invariant）

---

## 快速开始

### 1) 安装 Foundry
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 2) 初始化依赖（如使用 OpenZeppelin / forge-std）
在你的 Foundry 项目目录（例如 `labs/foundry-labs`）执行：
```bash
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit
```

### 3) 运行测试
```bash
forge test -vvv
```

### 4) 运行覆盖率
```bash
forge coverage
# 或输出 lcov
forge coverage --report lcov
```

### 5) 运行指定模块（示例）
```bash
# 漏洞库
forge test --match-path "test/vulns/*.t.sol" -vvv

# 不变量
forge test --match-path "test/invariant/*.t.sol" -vvv

# fork（需要 RPC）
ETH_RPC_URL=... forge test --match-path "test/fork/*.t.sol" -vvv
```

---

## 目录结构


```txt
web3-test-learning/
├── docs/
│   ├── 2026/
│   │   ├── 01/
│   │   ├── 02/
│   │   └── INDEX.md
│   ├── checklists/
│   │   ├── erc-test-points.md
│   │   ├── token-math-checklist.md
│   │   ├── oracle-risk-tests.md
│   │   ├── upgrade-governance.md
│   │   └── ...
│   ├── cheatsheets/
│   └── reports/
│       └── coverage.md
├── labs/
│   └── foundry-labs/
│       ├── foundry.toml
│       ├── src/
│       │   ├── examples/
│       │   ├── mocks/
│       │   └── testkit/
│       ├── test/
│       │   ├── templates/
│       │   ├── vulns/
│       │   ├── invariant/
│       │   └── fork/
│       └── script/
└── .gitlab-ci.yml (or .github/workflows/ci.yml)
```

---

## 12 周学习路线与交付物

### 第 1–2 周：Foundry 基础与 ERC 测试
**目标**：掌握 Foundry 测试写法 + ERC20/ERC721 行为与高频坑点。
**交付**：
- ERC20/721 单测（transfer/approve/transferFrom/safeTransferFrom 等）
- 1 个 fuzz + 1 条基础不变量（余额守恒/totalSupply 不变等）
- README：测试点清单 + 一键运行命令


---

### 第 3–4 周：漏洞回归库 Top10+
**目标**：把常见漏洞做成「可复现、可回归、可在 CI 阻断」的用例库。
**交付（至少 10 个主题）**：
- 重入（Reentrancy）
- 权限缺陷（onlyOwner/role）
- 初始化窗口（initializer）
- ERC20 approve 竞态
- 整数精度/舍入（rounding）
- 滑点缺失（minOut）
- Oracle 过期/操纵（stale/manipulation）
- Flash-loan 影响（同交易内瞬时状态）
- 升级权限/UUPS 风险（upgradeTo）
- DoS：gas grief / 大循环 / 存储膨胀


---

### 第 5–6 周：跨链与签名安全专项
**目标**：消息唯一性、域隔离、重放防护写成模板。
**交付**：
- 跨链消息模型：`srcChainId/srcApp/nonce/payload/messageId`
- 重放用例（同消息/跨 app/跨链）
- EIP-712 / Permit（EIP-2612）：nonce、deadline、domain separation、参数绑定
- 形成 checklist：跨链 & 签名


---

### 第 7–8 周：DeFi 场景化安全测试 + fork
**目标**：从“漏洞点”升级为“业务流”，并能在主网 fork 上做回归。
**交付（选 2 个做深）**：
- AMM/DEX：滑点、价格操纵、MEV 夹子简化、k-invariant
- 借贷：抵押率边界、清算触发、Oracle 更新前后边界变化
- Vault（ERC4626）：share/asset 换算、舍入套利边界回归


---

### 第 9–10 周：工程化与工具链（CI/覆盖率/Slither/Echidna）
**目标**：让仓库像团队项目一样可持续维护。
**交付**：
- GitLab CI / GH Actions：`forge test` + `forge coverage` + 失败日志可读性
- 质量门禁：coverage 阈值/关键用例失败阻断
- Slither：跑通 + 常见告警解释（reentrancy、unchecked-call 等）
- Echidna / Foundry invariant：至少 1 个最小例子 + 真实不变量


---

### 第 11–12 周：作品集包装与面试准备
**目标**：把“学过”变成“可验证能力”。
**交付**：
- 作品集首页：本 README + `docs/INDEX.md`（按周索引）
- 3 个最强案例写成漏洞报告格式（影响/复现/修复/回归）
- 面试讲解稿：每个项目 2 分钟（背景-问题-方案-结果）

---

## 测试策略（安全向）

建议你在每个主题都遵循同一套模板：

1) **Threat Model**：资产、信任边界、攻击面（外部调用、权限、价格源、跨链入口、升级入口）
2) **Failing Test（先红）**：把漏洞/风险先稳定复现
3) **Fix**：最小修复（CEI、ReentrancyGuard、nonce/domain、staleness check、minOut、slot 规划等）
4) **Regression（转绿 + 锁定）**：加“状态不变/余额守恒/关键指标不破”断言
5) **CI Gate**：关键回归失败必须阻断合并；覆盖率维持在合理阈值（先能用）

---

## CI 与质量门禁建议

门禁顺序（从易到难）：

- 必须通过：`forge test`
- 覆盖率：`forge coverage`（先设低阈值，例如 50%–60%，逐步提高）
- 关键回归阻断：例如 `test/vulns/*` 或 `test/templates/*` 必须全绿
- 静态扫描：Slither 报告作为 artifact（先不阻断，逐步治理误报）
- 不变量/模糊：invariant runs 先小（比如 128），再逐步加大

---

## FAQ

### Q1：为什么要同时做 fuzz / invariant？
- fuzz：快速找到边界输入导致的错误
- invariant：把系统“永远应该成立的真理”固化下来（资金守恒、权限不变、上限不破）

### Q2：为什么要做 fork？
- 真实协议/真实 token 的边界很多（特殊 decimals、fee-on-transfer、黑名单等）
- fork 回归能证明你具备“贴近生产”的测试能力

### Q3：我还有一个模板库仓库 `security-qa-playbook`，本仓库如何配合？
- 本仓库沉淀“每日/每周案例与学习轨迹”
- 模板库沉淀“团队级 test-kit + spec 模板 + checklist”
- 推荐做法：把模板库作为 submodule 引入本仓库（可选）

---

## License
MIT（或按你需要调整）
