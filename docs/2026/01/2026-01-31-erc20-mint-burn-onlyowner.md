# 2026-02-01 - Foundry D4：ERC20 mint/burn + onlyOwner 权限 + revert 分支测试

tags: [foundry, forge, solidity, erc20, mint, burn, onlyOwner, testing]

## 背景 / 目标
在 D1~D3 的基础上，今天把 ERC20 的供给侧能力补齐，并把「权限控制 + 自定义错误 + revert 断言」这一套测试模板跑通：
1. 实现 mint / burn（以及 burnFrom）
2. 引入 owner + onlyOwner（限制 mint，或更严格地限制 mint/burn）
3. 使用自定义 error 表达失败原因（更省 gas、也更利于测试精确断言）
4. 测试覆盖正常路径 + revert 分支：状态变化、事件校验、expectRevert（selector + 参数）

---

## 今日完成清单
- [ ] 合约新增：`owner`、`onlyOwner`、`transferOwnership`（可选）
- [ ] 实现 `_mint(to, amount)`：`totalSupply`、`balanceOf`、`Transfer(0, to, amount)`
- [ ] 实现 `_burn(from, amount)`：余额检查、`totalSupply`、`Transfer(from, 0, amount)`
- [ ] 对外函数：
  - [ ] `mint(to, amount)`：onlyOwner
  - [ ] `burn(amount)`：任何人可 burn 自己
  - [ ] `burnFrom(from, amount)`：需要 allowance（扣 allowance 后 burn）
- [ ] 自定义错误 + revert 分支测试：
  - [ ] 非 owner 调用 mint -> revert Unauthorized
  - [ ] mint 到 `address(0)` -> revert InvalidAddress
  - [ ] burn 余额不足 -> revert InsufficientBalance
  - [ ] burnFrom allowance 不足 -> revert InsufficientAllowance
- [ ] Foundry 测试：正常路径 + 事件断言（expectEmit）

---

## 实现要点

### 1) owner 与 onlyOwner
**模式：**
- 在构造函数里 `owner = msg.sender;`
- `modifier onlyOwner { if (msg.sender != owner) revert Unauthorized(msg.sender); _; }`

**可选增强：**
- `transferOwnership(address newOwner)`，并禁止 `newOwner == address(0)`。

---

### 2) mint / burn 的事件语义（非常关键）
- mint：必须触发 `Transfer(address(0), to, amount)`
- burn：必须触发 `Transfer(from, address(0), amount)`

这也是外部（钱包 / indexer）识别「增发/销毁」的惯例语义。

---

### 3) 推荐结构：内部无权限函数 + 外部权限封装
建议把核心账本逻辑放到内部函数，外部函数再叠加权限/参数检查，结构清晰：
- `_mint(to, amount)`：只管账本变化 + 事件
- `_burn(from, amount)`：只管账本变化 + 事件
- `mint(...)`：onlyOwner
- `burn(...)`：msg.sender 自己 burn
- `burnFrom(...)`：检查 allowance -> 扣 allowance -> `_burn(from, amount)`

---

## 自定义 error 设计（建议）
```solidity
error Unauthorized(address caller);
error InvalidAddress();
error InsufficientBalance(address from, uint256 have, uint256 need);
error InsufficientAllowance(address owner, address spender, uint256 have, uint256 need);
```

> 测试时可用 `abi.encodeWithSelector(ErrorName.selector, ...)` 精确断言。

---

## 测试用例设计（D4 核心）

### A. 正常路径（状态 + 事件）
1. **owner mint 成功**：supply 增加、alice balance 增加、Transfer(0->alice) 事件
2. **alice burn 成功**：supply 减少、alice balance 减少、Transfer(alice->0) 事件
3. **burnFrom 成功**：allowance 减少、余额/供给减少、Transfer(from->0) 事件

### B. revert 分支（expectRevert）
1. **非 owner mint**：`Unauthorized(caller)`
2. **mint to zero**：`InvalidAddress()`
3. **burn 余额不足**：`InsufficientBalance(from, have, need)`
4. **burnFrom allowance 不足**：`InsufficientAllowance(owner, spender, have, need)`

---

## expectEmit / expectRevert 模板

### 1) 事件断言模板（Transfer）
> 注意：indexed 参数（from/to）在 topic 里，value 在 data 里

```solidity
vm.expectEmit(true, true, false, true, address(token));
emit Transfer(from, to, value);
```

**小技巧：**  
在测试合约里声明一个同名 `event Transfer(...)`，用于 emit 匹配。

---

### 2) 自定义 error 的 revert 断言模板
```solidity
vm.expectRevert(abi.encodeWithSelector(SimpleERC20.Unauthorized.selector, caller));
```

无参数 error：
```solidity
vm.expectRevert(SimpleERC20.InvalidAddress.selector);
```

---

## 推荐的命令（只跑 D4）
```bash
forge test --match-path test/SimpleERC20.MintBurn.t.sol -vvv
# 或者只跑单个测试
forge test --match-test test_burn_success_updatesSupplyAndBalance_andEmitsTransfer -vvv
```

---

## 常见踩坑清单
1. **Transfer 事件 from/to 写反**：mint 必须 from=0；burn 必须 to=0
2. `vm.expectRevert` 必须写在调用前
3. `abi.encodeWithSelector` 的参数顺序必须与 error 定义一致
4. `burnFrom` 一定要先检查 allowance，再扣 allowance，然后 burn（这样 revert 原因更准确）

---

## 今日产出建议（文档/索引/提交）
### 1) docs 文件命名建议
- `docs/2026/02/2026-02-01-mint-burn-onlyowner.md`（本文件）

### 2) INDEX.md 增量条目（示例）
```md
- 2026-02-01  [foundry][erc20] mint/burn + onlyOwner + revert 分支测试（error/expectRevert/expectEmit）
```

### 3) 总 commit message（建议）
```text
feat(erc20): add mint/burn with onlyOwner + custom errors and tests
```
