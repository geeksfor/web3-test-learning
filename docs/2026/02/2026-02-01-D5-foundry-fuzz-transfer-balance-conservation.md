# 2026-02-01 - D5 Foundry Fuzz：随机 amount 的 transfer 后余额守恒（限制范围）+ VS Code 智能提示修复

tags: [foundry, forge, solidity, testing, fuzz, vscode]

## 背景 / 目标
今天的目标是把 Foundry **fuzz test（随机测试）** 跑通，并形成可复用模板：

1. 为 ERC20 `transfer(to, amount)` 增加 **fuzz**：随机生成 `amount`，验证**余额守恒**与关键不变量  
2. 学会用 `bound`（或 `vm.assume`）对 fuzz 输入做**限制范围**，避免无意义样本或频繁 revert  
3. 解决 VS Code 对 `vm.prank / vm.expectRevert / assertEq` 等 **forge-std 常用函数不提示**的问题（通常是 remapping 解析失败）

---

## 今日完成清单
- [x] 理解 fuzz 测试为何需要测试函数**带参数**：由 Foundry 自动注入随机值  
- [x] 写出 `testFuzz_transfer_balanceConservation(uint256 amount)` 模板  
- [x] 用 `bound(amount, 1, INIT)` 将 `amount` 限制到有效区间，避免 revert  
- [x] 学会用 `forge test --match-test/--match-contract` 精确运行该测试，并可用 `--fuzz-runs` 加强强度  
- [x] 修复 VS Code IntelliSense：生成 `remappings.txt` 并 Reload Window

---

## 核心知识点

### 1) 为什么 fuzz 测试函数需要带参数？
- **确定性测试**（你之前写的）：不带参数，输入你在函数体里写死（例如 `amount = 1 ether`）  
- **fuzz 测试**：带参数，Foundry 会多次执行该测试，并自动为参数生成**大量随机值**（例如 `amount`）

简化理解：
- 以前：1 个测试 = 1 组输入  
- fuzz：1 个测试 = 1 类输入空间（工具帮你探索边界）

### 2) “余额守恒”该断言什么？
对没有手续费/燃烧/铸币的 ERC20 `transfer(from -> to, amount)`：

- `alice.balance + bob.balance` **不变**
- `totalSupply` **不变**
- `alice.balance` 变为 `beforeAlice - amount`
- `bob.balance` 变为 `beforeBob + amount`

> 注：`to == from` 时转账前后余额不变，仍守恒，但覆盖价值较低；D5 先固定 to=bob 即可。

### 3) 限制 fuzz 输入：`bound` vs `vm.assume`
- **推荐 `bound`**：把随机值“折叠”到区间内，样本不会被丢弃，测试更稳定
- `vm.assume`：不满足条件的输入会被丢弃；如果丢弃过多可能导致 fuzz 失败或覆盖不足（“too many rejected inputs”）

---

## 代码模板：Fuzz + 余额守恒（推荐写法：bound）

> 文件建议：`test/SimpleERC20Fuzz.t.sol`

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleERC20.sol";

contract SimpleERC20FuzzTest is Test {
    SimpleERC20 token;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    uint256 constant INIT = 100 ether;

    function setUp() public {
        token = new SimpleERC20();
        token.mint(alice, INIT);
    }

    function testFuzz_transfer_balanceConservation(uint256 amount) public {
        // 1) 限制 amount：1..INIT（确保不会 revert）
        amount = bound(amount, 1, INIT);

        // 2) 记录转账前状态
        uint256 a0 = token.balanceOf(alice);
        uint256 b0 = token.balanceOf(bob);
        uint256 s0 = token.totalSupply();

        // 3) 执行：模拟 alice 调用 transfer 给 bob
        vm.prank(alice);
        token.transfer(bob, amount);

        // 4) 断言：两人余额和守恒、totalSupply 不变、各自变化正确
        uint256 a1 = token.balanceOf(alice);
        uint256 b1 = token.balanceOf(bob);
        uint256 s1 = token.totalSupply();

        assertEq(a1, a0 - amount);
        assertEq(b1, b0 + amount);
        assertEq(a1 + b1, a0 + b0);
        assertEq(s1, s0);
    }
}
```

---

## 可选：assume 写法（了解即可，不推荐作为主方案）

```solidity
function testFuzz_transfer_assume(uint256 amount) public {
    uint256 a0 = token.balanceOf(alice);

    vm.assume(amount > 0 && amount <= a0);

    vm.prank(alice);
    token.transfer(bob, amount);

    assertEq(token.balanceOf(alice), a0 - amount);
}
```

---

## 运行命令

### 1) 只跑某个合约 + 某个测试函数
```bash
forge test --match-contract SimpleERC20FuzzTest --match-test testFuzz_transfer_balanceConservation -vvv
```

### 2) 加大 fuzz 次数（更“狠”）
```bash
forge test --match-test testFuzz_transfer_balanceConservation --fuzz-runs 2000 -vvv
```

---

## VS Code 没有提示：最常见原因与修复步骤

**现象：** `vm.prank / vm.expectRevert / assertEq` 无补全，`import "forge-std/Test.sol";` 可能还报红或无法跳转。

**根因：** VS Code 的 Solidity Language Server 没能解析到 Foundry 的依赖路径（remappings）。

### 修复步骤（推荐）
在项目根目录执行：
```bash
forge remappings > remappings.txt
```

确认 `remappings.txt` 有类似内容：
```txt
forge-std/=lib/forge-std/src/
@openzeppelin/=lib/openzeppelin-contracts/
```

然后在 VS Code：
- Command Palette（⌘⇧P）→ `Developer: Reload Window`

> 额外检查：确保 `lib/forge-std` 真存在；否则先 `forge install foundry-rs/forge-std`。

---

## 今日踩坑 / 经验
1. fuzz 输入不限制会频繁 revert（amount > balance），导致测试几乎全失败或无效  
2. `bound` 比 `vm.assume` 更稳定：不丢样本、覆盖更高  
3. VS Code 不提示通常不是 Foundry 本身问题，而是 **remappings / 依赖解析**问题

---

## 下一步（D6 预告）
- fuzz `to` 地址 + `amount`：增加 `vm.assume(to != address(0) && to != alice)`  
- 引入更强的不变量（invariant）测试：对一系列随机操作维持不变量

---

## 建议 Commit Message
**feat(foundry): add fuzz test for ERC20 transfer conservation + vscode remappings**

（如果你把 remappings.txt 也提交到仓库，建议一并提交）
