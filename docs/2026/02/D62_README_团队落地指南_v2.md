# D62：README — 如何在团队落地（Foundry 漏洞库 / 测试库）

> 目标：把“个人能跑”升级为“团队能用、能维护、能持续集成”的落地说明。  
> 适用：本仓库的 Foundry 漏洞库/测试库（`labs/foundry-labs`）。

---

## 1. 你要解决的团队问题是什么

团队落地通常会遇到 4 类问题：

1) **新人上手慢**：不知道要装什么、从哪里开始跑、跑哪些。  
2) **环境不一致**：本地能跑，CI/别人机器跑不起来（依赖、remappings、版本漂移）。  
3) **缺少质量门禁**：测试/覆盖率没有“硬标准”，无法阻断回归。  
4) **问题定位困难**：失败日志读不懂，缺少关键状态打印与调试入口（console2/snapshot）。

本 README 的“落地章节”就是围绕这 4 件事给出可复制流程。

---

## 2. 推荐的团队使用方式（两种模式）

### 模式 A：作为“可复用漏洞库/训练场”（推荐）
- 作为团队共享的**安全测试用例仓库**，用于：
  - 新人训练（每个 Dxx 一类风险点）
  - 审计/测试 checklist 的落地验证（把 checklist 变成用例）
  - 回归基线（修复后必须有回归测试）

特点：迭代快、复用强，但不要与线上业务耦合过深。

### 模式 B：作为“业务协议的测试模板”
- 把关键测试框架、工具、CI 门禁、日志可读性能力迁移到业务仓库：
  - 只保留你们业务需要的那部分测试结构/工具库
  - 关键用例沉淀为业务回归

特点：更贴近生产，但需要更严谨的目录结构与发布流程。

---

## 3. 目录结构与约定（团队协作必须明确）

建议保持如下结构（示例）：

```
labs/foundry-labs/
  ├── src/                     # 合约/最小化示例
  ├── test/
  │   ├── vulns/                # ✅ 漏洞库（默认 CI 跑）
  │   ├── fork/                 # Fork 场景（需要 RPC；CI 条件跑）
  │   └── utils/                # ✅ 调试/断言/测试工具库（D60 产物）
  ├── script/                   # 部署/脚本（不影响 vulns 的可跑性）
  ├── foundry.toml
  ├── remappings.txt
  └── lib/                      # forge-std / openzeppelin 等依赖（submodule 或 install）
```

团队约定建议写进 README：

- **测试命名**：`Dxx_主题_风险点.t.sol`，测试函数名用 `test_...` 清晰表达预期。  
- **用例等级**：`critical` / `non-critical`（关键子集门禁更好落地）。  
- **fork 用例隔离**：统一放 `test/fork/`，避免 CI 没 RPC 就全红。

---

## 4. 本地开发工作流（团队统一入口）

### 4.1 环境要求
- Foundry（建议 stable）
- Git（若依赖用 submodule）

### 4.2 一键启动（新人照做即可）
在仓库根目录：

```bash
# 初始化子模块（如果你们用 submodule 管依赖）
git submodule update --init --recursive

# 进入 Foundry 工程
cd labs/foundry-labs

# 安装/更新 foundry
foundryup

# 编译
forge build

# 只跑漏洞库（推荐默认）
forge test --match-path "test/vulns/*.t.sol" -vvv

# 需要更详细 trace
forge test --match-path "test/vulns/*.t.sol" -vvvv
```

### 4.3 常用定位命令（建议写入 README）
```bash
# 只跑某个合约
forge test --match-contract D45_PriceManipulation_Test -vvvv

# 只跑某个测试函数
forge test --match-test test_attack_* -vvvv

# 失败时显示更多 gas/trace 信息
forge test -vvvv
```

---

## 5. CI/质量门禁（团队落地的核心）

### 5.1 CI 必须做什么
最小落地建议：

- ✅ `forge fmt --check`（格式统一）
- ✅ `forge test`（关键测试失败阻断）
- ✅ Coverage 门禁（阈值先低一点，比如 60%）
- ✅ Coverage 报告 artifact（便于 PR review）

你们可以把门禁写成“渐进式”：
- 初期：Lines >= 60%
- 稳定后：逐步提高到 70%、80%

### 5.2 推荐策略：关键集硬门禁 + 全量集软运行
- `test/vulns/critical/`：**硬门禁**（失败阻断）
- `test/vulns/` 全量：可在 nightly/手动触发跑，或者允许 continue-on-error

这样团队不会因为少量在修用例导致无法合并。

---

## 6. 失败日志可读性（团队维护成本的关键）

建议在 README 写清楚“遇到失败怎么排查”，并提供工具库入口：

- 使用 `console2` 打印关键状态
- 用 `snapshot()` / `diff()` 对比前后状态
- 对关键断言打印 `expected/actual/diff`
- 需要时用 `emit log_named_*` 进入 trace

推荐把 `test/utils/Debug.sol`（D60）作为团队默认工具，并在 README 链接到它。

---

## 7. 团队协作规范（建议写到 README）

### 7.1 分支 & 提交流程（建议）
- 分支：`test/dxx-<topic>` 或 `ci/dxx-<topic>`
- PR 必须：
  - 测试全绿（至少 critical 集合）
  - CI 通过（fmt/test/gate）
  - 如果是修复类：必须包含回归测试（先红后绿）

### 7.2 代码审查 checklist（适合你们做安全测试）
- 新用例是否能独立运行（不依赖外部 RPC）？
- 断言是否清晰（失败时能定位问题）？
- 是否覆盖边界（0、1、最大值、舍入、时间窗等）？
- 是否有日志/快照便于 debug？
- 修复是否有回归测试？

---

## 8. 团队推广/培训玩法（可选但很有效）

你可以在 README 增加一段“入门路线”：

- Day 1：跑通 vulns + 看懂 trace  
- Day 2：选一个 Dxx 改造成你们真实业务的风险点测试  
- Day 3：给 CI 加门禁（coverage 60%）  
- Day 4：引入 fork 用例与 RPC secrets（可选）  
- Day 5：把 checklist → 用例映射表补齐（审计视角）

---

## 9. 常见问题（FAQ）

**Q1：为什么 CI 只跑 `test/vulns/`？**  
A：避免 fork/RPC/外部依赖导致 CI 不稳定。fork 用例放 `test/fork/`，条件触发。

**Q2：覆盖率低怎么办？**  
A：阈值先低一点，先让门禁“可用”；然后用 PR 增量提升，逐步抬阈值。

**Q3：失败日志看不懂怎么办？**  
A：统一用 D60 的调试工具库（console2 + snapshot），并要求每个新用例包含关键状态打印。

---

## 10. 建议放置位置（你问的“README 是哪个目录的？”）

- 如果你是为 **Foundry 漏洞库/测试库** 写“团队落地”说明：  
  ✅ 建议放在：`labs/foundry-labs/README.md`（或在该 README 增加一节 `## 团队落地`）

- 如果你是为 **整个仓库** 写总览与入口说明：  
  ✅ 建议放在：仓库根目录 `README.md`，并在里面链接到 `labs/foundry-labs/README.md` 的“团队落地”章节。

> 结论：本篇内容更贴合 Foundry 工程本身，因此优先放 `labs/foundry-labs/README.md`。

---

## 11. 可直接复制的 README 小节标题（建议）

你可以把下面标题直接拷贝到 `labs/foundry-labs/README.md`：

- `## 快速开始（团队版）`
- `## 目录结构与约定`
- `## 本地开发工作流`
- `## CI 与质量门禁（fmt/test/coverage gate）`
- `## 失败排查指南（console2/snapshot/trace）`
- `## 协作规范（分支/PR/回归测试）`
- `## FAQ`

---
