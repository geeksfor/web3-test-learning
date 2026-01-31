# 2026-01 学习索引（INDEX）

> 位置建议：`docs/2026/01/INDEX.md`  
> 用途：快速回顾当月每天的学习主题、入口文档、对应的可运行代码位置。

---

## 快速入口

- Foundry 工程目录：`labs/foundry-labs`
- 常用命令（在 Foundry 工程目录执行）：
```bash
cd labs/foundry-labs
forge test -vvv
```

---

## 每日学习日志

### D1 — Foundry 环境搭建 + 第一个测试（Counter）
- 📄 文档：[`2026-01-29-foundry-setup-first-test.md`](./2026-01-29-foundry-setup-first-test.md)
- 📦 代码：`labs/foundry-labs/src/Counter.sol`
- 🧪 测试：`labs/foundry-labs/test/Counter.t.sol`

---

### D2 — Foundry 测试进阶：prank / expectRevert + ERC20 transfer 正常/异常 + 指定跑测试
- 📄 文档：[`2026-01-30-Foundry-learn.md`](./2026-01-30-Foundry-learn.md)
- 📦 代码：`labs/foundry-labs/src/SimpleERC20.sol`
- 🧪 测试：`labs/foundry-labs/test/SimpleERC20.t.sol`

---

### D3-1 — ERC20 Allowance 全链路：approve / transferFrom + 事件校验 + 自定义错误精确匹配
- 📄 文档：[`2026-01-31-erc20-allowance.md`](./2026-01-31-erc20-allowance.md)
- 📦 代码：`labs/foundry-labs/src/SimpleERC20.sol`
- 🧪 测试：`labs/foundry-labs/test/SimpleERC20allowance.t.sol`
- ▶️ 运行：
```bash
cd labs/foundry-labs
forge test -vvv --match-contract SimpleERC20AllowanceTest
```
### D3-2 — [foundry][erc20] mint/burn + onlyOwner + revert 分支测试（error/expectRevert/expectEmit
- 📄 文档：[`2026-01-31-erc20-mint-burn-onlyowner.md`](./2026-01-31-erc20-mint-burn-onlyowner.md)
- 📦 代码：`labs/foundry-labs/src/SimpleERC20.sol`
- 🧪 测试：`labs/foundry-labs/test/SimpleERC20.MintBurn.t.sol`
- ▶️ 运行：
```bash
cd labs/foundry-labs
forge test -vvv --match-contract SimpleERC20MintBurnTest
```

---

## 复盘清单（每篇文档建议都包含）

- [ ] 今日目标（完成标准）
- [ ] 最小实现点（合约/测试的关键代码块）
- [ ] 覆盖的正常/异常用例列表
- [ ] 至少 1 个“踩坑记录/trace 定位”
- [ ] 如何运行（含单测过滤命令）
- [ ] 面试 30 秒讲解版本（Talk Track）

---

## 如何新增一天（模板）
1. 在 `docs/2026/01/` 新建当日文档：`YYYY-MM-DD-<topic>.md`
2. 在本 INDEX 里新增一段（D4/D5…），补上：
   - 文档链接
   - 对应的合约/测试路径
   - 一条可直接复制运行的命令
