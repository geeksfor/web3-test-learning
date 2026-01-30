# 2026-01-30 - Foundry 测试进阶：vm.prank / vm.startPrank / vm.expectRevert + ERC20 transfer 正常/异常 + 指定跑测试

tags: [foundry, forge, solidity, testing, setup]

## 背景 / 目标
今天目标是把 Foundry 测试里最常用的三类能力跑通一遍，形成可复用模板：
1. 学会用 vm.prank / vm.startPrank 模拟不同调用者（控制 msg.sender）

2. 学会用 vm.expectRevert 断言异常分支（例如 ERC20 转账余额不足）

3. 学会用 forge test 指定跑某个测试合约/文件/函数，并理解为什么脚本编译错误会挡住测试（forge test --match-path test/SimpleERC20.t.sol --match-contract SimpleERC20Test --match-test test_transfer
）

## 今日完成清单
- 学会 vm.prank：只影响下一次调用的 msg.sender

- 学会 vm.startPrank / vm.stopPrank：一段连续调用统一 sender

- 学会 vm.expectRevert：断言下一次调用必然 revert（支持精确匹配 error selector + 参数）

- 实现最小 ERC20（含 mint + transfer + 自定义错误 InsufficientBalance）

- 编写 ERC20 transfer 测试：正常转账 / 余额不足异常

- 掌握 forge test --match-contract/--match-test/--match-path

- 解决“指定跑测试但仍编译失败”的根因：Forge 会先编译整个项目（含 script）

## 关键知识点（用自己的话总结）
1. Foundry 的 cheatcodes（测试里的“超能力”）：
   - vm.prank(addr)：让下一次外部调用的 msg.sender = addr（一次性）
   - vm.startPrank(addr)：从当前行开始，让后续多次调用的 msg.sender = addr，直到 vm.stopPrank()
   - vm.expectRevert()：断言下一次调用会 revert（不关心原因）
   - vm.expectRevert(bytes)：断言下一次调用按指定 revert 数据失败（推荐用自定义 error selector 来精确匹配）
   - prank = 一次性面具；startPrank = 持续伪装；expectRevert = 先声明“下一次必失败”。
2. ERC20 transfer 的两条核心测试线：
   - 正常路径：余额充足时，from 减、to 加，返回值 true（可选）
   - 异常路径：余额不足时必须 revert，并且状态不能变化（余额不变）
3. forge test 的“过滤只影响运行，不影响编译”：
   - forge test --match-contract SimpleERC20Test Forge 仍会先编译整个项目（src/ + test/ + script/），所以 script 里构造函数参数写错也会导致测试直接跑不起来。
4. 指定跑哪个测试（常用命令）
  - 按测试合约名(forge test --match-contract SimpleERC20Test)
  - 按照函数名(forge test --match-test test_transfer_ok_prank)
  - 按测试文件路径(forge test --match-path test/SimpleERC20.t.sol)
  - 组合（更精准）(forge test --match-path test/SimpleERC20.t.sol --match-contract SimpleERC20Test --match-test test_transfer)

## 代码连接
labs/foundry/src/SimpleERC20.sol
labs/foundry/test/SimpleERC20.t.sol

## 总结
今天把 Foundry 测试里最常见的三件事打通了：
模拟调用者（prank）→ 覆盖正常/异常分支（expectRevert）→ 精准筛选运行（match-*）并能处理“编译挡路”的问题。
