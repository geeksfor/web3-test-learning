# 2026-01-29 - Foundry 环境安装 + 创建项目 + 跑通首个 forge test

tags: [foundry, forge, solidity, testing, setup]

## 背景 / 目标
今天完成 Foundry 的环境安装（foundryup），创建第一个项目并成功跑通 `forge test`。
同时写了第 1 个测试：完成合约部署 + 基本断言，形成最小可运行的测试闭环。

## 今日完成清单
- [x] 安装 Foundry（foundryup）
- [x] 初始化项目（forge init）
- [x] 跑通测试（forge test）
- [x] 编写首个测试：部署合约 + 基本断言

## 关键知识点（用自己的话总结）
1. Foundry 的核心工具：
   - `forge`：编译/测试/脚本
   - `cast`：链上交互工具（调用合约、编码解码等）
   - `anvil`：本地节点（本地链）
2. `forge test` 的最小闭环：
   - `src/` 写合约
   - `test/` 写测试（Solidity）
   - `forge test` 运行并得到断言结果
3. 测试的最小结构：
   - `setUp()`：每个用例前的初始化（部署合约、准备变量）
   - `testXXX()`：以 `test` 开头的方法会被自动识别为测试用例
   - 常用断言：`assertEq`、`assertTrue`

## 实操步骤（最小复现）
### 1) 安装 Foundry
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
forge --version
cast --version
anvil --version

### 代码连接
labs/foundry/src/Counter.sol
labs/foundry/test/Counter.t.sol

## 总结
已具备最小可复现的 Foundry 测试闭环：安装 → 初始化 → 编写合约 → 编写测试 → 跑通断言
