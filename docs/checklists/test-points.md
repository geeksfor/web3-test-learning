# Test Points Checklist (Detailed)

> 这里放“函数级”测试点清单；根目录 README 只保留模块级概览，避免越写越大。

## A. ERC20 Transfer（`test/SimpleERC20.t.sol`）
- [x] prank 只影响一次调用：`test_prank_only_once`
- [x] transfer 成功（prank）：`test_transfer_ok_prank`
- [x] transfer 成功（startPrank）：`test_transfer_ok_startPrank`
- [x] transfer 失败：余额不足（精确校验）：`test_transfer_revert_insufficient_balance_exact`
- [x] transfer 失败：余额不足（简单校验）：`test_transfer_revert_insufficient_balance_simple`

### 建议补漏（提升 branches/funcs）
- [ ] transfer to zero 地址 revert（如合约有该检查）
- [ ] transfer amount==0 行为（允许并 emit Transfer / 或 revert，按合约实现）
- [ ] 事件校验覆盖更多分支（如当前 transfer 成功未校验事件）

---

## B. Mint / Burn / BurnFrom（`test/SimpleERC20.MintBurn.t.sol`）
- [x] ownerMint 成功：supply + balance + Transfer(0,to,amount)
  - `test_ownerMint_success_updatesSupplyAndBalance_andEmitsTransfer`
- [x] mint 非 owner 调用 revert：`test_mint_revert_whenNotOwner`
- [x] mint to zero revert：`test_mint_revert_whenToZero`
- [x] burn 成功：supply + balance + Transfer(from,0,amount)
  - `test_burn_success_updatesSupplyAndBalance_andEmitsTransfer`
- [x] burn 余额不足 revert：`test_burn_revert_whenInsufficientBalance`
- [x] burnFrom 成功：allowance 减少 + burn 生效：`test_burnFrom_success_reducesAllowance_andBurns`
- [x] burnFrom allowance 不足 revert：`test_burnFrom_revert_whenInsufficientAllowance`

### 建议补漏（提升 branches）
- [ ] burnFrom 无限 allowance 分支（如实现里对 `type(uint256).max` 特判）
- [ ] burn amount==0 行为（按合约实现）

---

## C. Allowance / transferFrom（`test/SimpleERC20allowance.t.sol`）
- [x] approve 写入 allowance + Approval 事件：`test_Approve_SetsAllowance_AndEmitsApproval`
- [x] approve overwrite（非累加）+ 两次事件：`test_ApproveOverwrite_NotAccumulate_EmitsTwice`
- [x] transferFrom 成功：balance/allowance + Transfer/Approval 事件
  - `test_transferFrom_success_balance_allowance_and_events`
- [x] transferFrom allowance 不足 revert：`test_transferFrom_reverts_whenAllowanceInsufficient`
- [x] transferFrom 余额不足 revert（即使 allowance 足够）：
  - `test_transferFrom_RevertWhenBalanceInsufficient_EvenIfAllowanceEnough`
- [x] 无限 allowance：spend 后 allowance 不减少（且只校验 Transfer）：
  - `test_InfiniteAllowance_DoesNotDecrease_AndEmitsOnlyTransferForSpend`

### 建议补漏（提升 branches）
- [ ] approve spender==0 revert（如合约有该检查）
- [ ] transferFrom to==0 revert（如合约有该检查）
- [ ] transferFrom amount==0 行为（按合约实现）

---

## D. Fuzz（`test/SimpleERC20.Fuzz.t.sol`）
- [x] transfer 后余额守恒（runs: 256）：
  - `testFuzz_transfer_balanceConservation(uint256)`

### 建议补漏（fuzz 深化）
- [ ] 多参与者守恒（alice/bob/carol 随机转）
- [ ] fuzz 增加 runs/seed 复现机制（README/日志记录）

---

## E. Counter 示例（`test/Counter.t.sol`）
- [x] 部署初始化断言：`test_DeployAndInitValue`
- [x] setNumber：`test_SetNumber`
- [x] increment：`test_Increment`
