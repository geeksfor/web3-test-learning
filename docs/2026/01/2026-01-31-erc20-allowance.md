# 2026-01-31 - ERC20 Allowance 全链路：approve / transferFrom + allowance 变化 + 事件校验 + 自定义错误精确匹配

tags: [foundry, forge, solidity, testing, erc20, allowance]

## 背景 / 目标
今天目标是把 ERC-20 授权体系（allowance）完整跑通一遍，形成可复用的测试模板：

1. 实现并理解 `approve(spender, amount)`：设置 allowance，并触发 `Approval` 事件  
2. 实现并理解 `transferFrom(from, to, amount)`：校验 & 消耗 allowance，完成代扣转账，并触发事件  
3. 用 Foundry 覆盖 **正常/异常** 两条核心线：
   - 正常路径：allowance 足够 → 余额变化正确 + allowance 扣减正确 + 事件正确  
   - 异常路径：allowance 不足 → 必须 revert（可精确匹配 custom error selector + 参数）  
4. 掌握 “为什么 expectRevert 失败” 的定位方式：从 trace 看单位、参数、selector 是否一致

---

## 今日完成清单
- 实现 allowance 存储结构：`allowance[owner][spender]`
- 实现 `approve`：更新 allowance + emit Approval
- 实现 `transferFrom`：校验 allowance + 扣减 allowance + 转账 + emit Transfer（可选：扣减后 emit Approval）
- 编写 allowance 全链路测试：
  - approve 设置 allowance + Approval 事件校验（vm.expectEmit）
  - transferFrom 正常：余额变化 + allowance 扣减 + Transfer 事件校验
  - transferFrom 异常：allowance 不足 revert（vm.expectRevert 精确匹配）
- 解决真实踩坑：
  - “6”和“6 ether”的单位差异导致本该 revert 的用例没 revert
  - custom error 的参数精确匹配必须与合约实际 revert 数据一致（5 vs 5e18）

---

## 关键知识点（用自己的话总结）

1. allowance 是 ERC-20 的“授权额度表”（二维 mapping）
   - owner 授权 spender 能从 owner 账户里花多少
   - 数据结构：`allowance[owner][spender] -> amount`

2. approve 的语义：覆盖式赋值，不是累加
   - `approve(bob, 10)` 再 `approve(bob, 20)` → allowance 变成 20
   - 触发 `Approval(owner, spender, amount)` 事件（前端/索引依赖它）

3. transferFrom 的语义：spender 代替 owner 花钱（需要授权）
   - spender = `msg.sender`
   - 必须先校验 `allowance[from][spender] >= amount`
   - 校验通过才允许执行余额转移 `from -> to`
   - allowance 一般会扣减（有些实现支持 max allowance 不扣减，属优化点）

4. 事件校验是“全链路测试”的一部分（不仅仅断言状态）
   - `Approval(owner, spender, value)`：授权变化对外可见
   - `Transfer(from, to, value)`：资产流转对外可见
   - 用 `vm.expectEmit(...)` + `emit Event(...)` 方式精确校验

5. vm.expectRevert 的本质：声明“下一次调用必须失败”
   - `vm.expectRevert()`：只要 revert 就行（不关心原因）
   - `vm.expectRevert(selector)`：要求错误类型一致（自定义 error selector）
   - `vm.expectRevert(abi.encodeWithSelector(...))`：要求错误类型 + 参数完全一致（最严格）

6. 今天最关键的坑：单位（wei vs ether）会直接导致 revert 分支跑偏
   - `approve(bob, 5 ether)` 存进去是 `5e18`
   - `transferFrom(..., 6)` 实际是 6 wei（远小于 5e18）→ 不会 revert
   - 预期要测试“5 ether 不够花 6 ether”，必须写 `6 ether`

7. custom error 参数精确匹配：必须和合约实际 revert 输出一致
   - 实际：`InsufficientAllowance(bob, 5e18, 6e18)`
   - 期望写成：`InsufficientAllowance(bob, 5, 6)` 会失败
   - 正确：`InsufficientAllowance(bob, 5 ether, 6 ether)`

---

## 推荐测试模板（今天沉淀出的写法）

### 1）approve：状态 + 事件
- `vm.prank(alice)` → alice 发起 approve
- `vm.expectEmit(...)` + `emit Approval(alice, bob, 5 ether)`
- `token.approve(bob, 5 ether)`
- `assertEq(token.allowance(alice, bob), 5 ether)`

### 2）transferFrom 不足：精确匹配 revert
- `alice approve bob 5 ether`
- `bob transferFrom(..., 6 ether)` 应 revert
- `vm.expectRevert(abi.encodeWithSelector(InsufficientAllowance.selector, bob, 5 ether, 6 ether))`

---

## 指定跑测试（今天实际使用的命令）

> 注意：你的 Foundry 工程在 `labs/foundry-labs`，所以要先 `cd` 进去再跑。

```bash
cd labs/foundry-labs

# 跑 allowance 测试合集
forge test -vvv --match-contract SimpleERC20AllowanceTest

# 跑单条用例
forge test -vvv \
  --match-contract SimpleERC20AllowanceTest \
  --match-test test_transferFrom_reverts_whenAllowanceInsufficient
```

必要时清缓存：
```bash
forge clean && forge test -vvv
```

---

## 代码链接
- 合约：`labs/foundry-labs/src/SimpleERC20.sol`
- 测试：`labs/foundry-labs/test/SimpleERC20allowance.t.sol`

---

## 总结
今天把 ERC-20 的 allowance 授权体系完整跑通了：  
**approve（设置额度 + Approval） → transferFrom（校验/扣减额度 + 转账 + Transfer） → 覆盖正常/异常分支 → 事件校验 + custom error 精确匹配**。

并且沉淀了一个很实用的 Debug 经验：  
**看 trace 先看单位**（`6` vs `6 ether`），再看 **error selector + 参数** 是否一致，否则 `expectRevert` 会“看起来对，但就是不匹配”。
