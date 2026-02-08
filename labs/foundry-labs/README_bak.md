# Foundry 学习仓库：ERC20 测试 + Allowance + Mint/Burn + Fuzz

本仓库用于系统化练习 **Foundry** 测试，当前已覆盖：

- ERC20 `transfer` 正常/异常（余额不足）
- `approve / transferFrom` 全链路（allowance 变化、事件校验、无限 allowance）
- `mint/burn/burnFrom`（含 `onlyOwner` 权限、零地址校验、事件校验）
- Fuzz：`transfer` 后余额守恒（约束范围）
- Counter：Foundry 入门示例

> 说明：根目录 `README.md` 只保留“入口级”信息；更细的函数级测试点、每日日志、覆盖率演进记录统一放在 `docs/` 下，避免 README 越写越大。

---

## 环境

- Solidity：`^0.8.x`
- Foundry：`forge`

---

## 快速开始

```bash
# 1) 安装依赖（如有 forge-std / 其它库）
forge install

# 2) 编译
forge build

# 3) 跑全部测试
forge test -vvv
```

---

## 运行方式（常用命令）

### 全量测试
```bash
forge test -vvv
```

### 指定跑某个文件 / 合约 / 测试函数
```bash
# 按文件
forge test --match-path test/SimpleERC20.t.sol -vvv

# 按合约
forge test --match-contract SimpleERC20AllowanceTest -vvv

# 按函数
forge test --match-test test_transferFrom_success_balance_allowance_and_events -vvv
```

### 只跑 fuzz（或限制 fuzz）
```bash
forge test --match-test testFuzz_ -vvv
# 可选：提高 fuzz 次数
forge test --match-test testFuzz_ --fuzz-runs 1000 -vvv
```

---

## 测试点清单（高层概览）

- **ERC20 Transfer**：成功/余额不足异常分支（含 prank / startPrank 场景）
- **Allowance**：approve overwrite、transferFrom 全链路、无限 allowance
- **Mint/Burn**：onlyOwner、to zero 校验、burnFrom allowance 分支
- **Fuzz**：transfer 后余额守恒性质测试
- **Counter**：Foundry 入门示例

✅ **函数级详细清单（可勾选）见：** `docs/checklists/test-points.md`

---

## 覆盖率（Coverage）

### 跑覆盖率
```bash
forge coverage
```

### 生成 lcov + HTML（推荐，用于定位红线）
```bash
forge coverage --report lcov
genhtml lcov.info --output-directory coverage
# 打开 coverage/index.html 查看每行/分支覆盖情况
```

### 当前覆盖率（最近一次 Baseline）
```
src/Counter.sol     Lines 100.00% (6/6)   Statements 100.00% (3/3)   Branches 100.00% (0/0)  Funcs 100.00% (3/3)
src/SimpleERC20.sol Lines 89.86% (62/69)  Statements 86.15% (56/65)  Branches 61.54% (8/13)  Funcs 81.25% (13/16)
Total               Lines 90.67% (68/75)  Statements 86.76% (59/68)  Branches 61.54% (8/13)  Funcs 84.21% (16/19)
```

✅ **覆盖率演进记录（按日期追加）见：** `docs/reports/coverage.md`

---

## Docs（推荐阅读顺序）

- `docs/INDEX.md`：总索引（月份索引 + 主题索引）
- `docs/2026/02/index.md`：本月学习日志索引（每天新增一行链接即可）
- `docs/checklists/test-points.md`：函数级测试点清单（适合复盘/面试展示）
- `docs/reports/coverage.md`：覆盖率提升记录（每次补测后追加）

---

## 目录结构（示例）

```
src/
  Counter.sol
  SimpleERC20.sol

test/
  Counter.t.sol
  SimpleERC20.t.sol
  SimpleERC20allowance.t.sol
  SimpleERC20.MintBurn.t.sol
  SimpleERC20.Fuzz.t.sol

docs/
  INDEX.md
  2026/01/index.md
  2026/02/index.md
  checklists/test-points.md
  reports/coverage.md
```

---

## 常见问题（FAQ）

### 1) 为什么 `forge test` 会跑全部测试？
Foundry 默认会编译并执行 `test/` 下所有 `*.t.sol` 文件中的测试合约。

### 2) 如何只跑某一个测试函数？
```bash
forge test --match-test test_transfer_ok_prank -vvv
```

### 3) README 会不会越写越大？
不会。根 README 只保留入口级内容；每天学习日志、函数级测试点、覆盖率演进都在 `docs/`。

---

## 可选：建议的 .gitignore
如果你不想提交覆盖率 HTML 产物，可在 `.gitignore` 增加：
```
coverage/
lcov.info
```

---

## License
学习用途（按项目实际情况填写）
