# D15 Reentrancy 学习问答知识点总结（基于本次对话）

> 目标：把你今天围绕 Reentrancy（重入）、MiniBank 示例、Foundry 测试工具（vm.*）的提问点，整理成可复习的一页笔记。

---

## 1. MiniBankVuln 是什么？遵循 ERC20 吗？

- **不是 ERC20，也不属于任何 ERC 标准**。
- 它只是一个“教学用最小银行/金库”模型：
  - `deposit()`：把 **ETH** 存入合约（需要 `payable`）
  - `withdraw(...) / withdrawAll()`：把 **ETH** 提出
  - `mapping(address => uint256) balanceOf`：**合约内部记账**（某个地址的“存款余额”）

> ERC20 的 `balanceOf(address)` 是 **代币合约内部账本**；MiniBank 的 `balanceOf[msg.sender]` 是 **存款记账**，概念相似但不是代币标准。

---

## 2. ETH 余额 vs 代币余额：为什么 `address(bank).balance` 不是 `bank.balanceOf`？

- `address(bank).balance`：读取 **地址账户层面的原生币（ETH）余额**（协议层维护）
  - 表示“银行合约这个地址，真实持有多少 ETH（资金池）”
- `bank.balanceOf(user)`：读取 **合约内部 mapping 记账余额**
  - 表示“银行合约账本里，user 存了多少（应该能提现多少）”

所以你说的情况完全正常：
- 你账户里 **有 100 ETH**
- 但某个 ERC20 代币合约里你可能 **代币余额为 0**

---

## 3. `call{value: amount}("")` 到底做了什么？会扣银行的 balance 吗？

```solidity
(bool ok, ) = msg.sender.call{value: amount}("");
require(ok, "transfer failed");
```

- 这是一种“低级外部调用”：
  - `{value: amount}`：**从当前合约（银行）转出 amount ETH**
  - `""`：**空 calldata**
- 如果 `ok == true`：
  - `address(bank).balance` 会 **立刻减少 amount**
  - 收款方余额增加 amount
  - 若收款方是合约，且 calldata 为空 → 会触发对方 `receive()`

---

## 4. `receive()` 是干什么的？为什么“没显式调用它”也会执行？

### 4.1 `receive()` 的设计初衷
- 让合约可以像普通地址一样 **接收 ETH**
- 并可在“收到 ETH 的瞬间”执行逻辑（记账、事件、自动分账等）

### 4.2 为什么会被触发？
- 当你向一个 **合约地址** 发送 ETH 且 calldata 为空：
  - EVM 会优先调用对方的 `receive() external payable`
- 所以：
  - `call{value: amount}("")` **就是**把 `amount` 作为 `msg.value` 交给对方的 `receive()`

> 如果对方 `receive()` 不是 `payable`，会因为“无法接收 ETH”而 revert，导致 `ok=false`。

---

## 5. `fallback()` 与“有 calldata 但找不到函数”怎么理解？

- calldata = 外部调用携带的数据（前 4 字节通常是函数 selector）
- **有 calldata 但找不到函数**：你发起了一个带 selector 的调用，但目标合约并没有对应的函数签名  
  → 就会走 `fallback()`（如果存在）

规则记忆：
- **calldata 为空**且转 ETH → 优先 `receive()`
- **calldata 非空**且没匹配到函数 → `fallback()`

---

## 6. `payable` 什么时候要加？

口诀：**“要收 ETH，就 payable；不收就别 payable。”**

需要 `payable` 的典型情况：
- 存款/购买/捐款等“付钱”函数：`deposit() external payable`
- `receive()`：必须 payable 才能接 ETH
- `fallback()`：如果你希望未知调用也能收 ETH，则设为 payable

通常不加 payable：
- 配置/授权/提款函数（withdraw 通常不需要收钱）

---

## 7. `to.transfer(...)` 是固定写法吗？`sweep()` 是什么？

- `transfer` 是 **`address payable`** 的成员函数，用于转 ETH：
  - `to.transfer(amount)`：失败会 revert（且 gas 限制较严格）
- `sweep(to)` 的含义：
  - 把攻击合约自身余额 `address(this).balance` 一次性转到 `to`
  - 相当于“把攻击合约里攒到的 ETH 提走”
- 教学版 sweep 常没加权限；真实项目应加 `onlyOwner` 防止任何人把钱转走。

---

## 8. CEI（Checks-Effects-Interactions）为什么能防重入？

重入的根源：**你把控制权交给外部合约（interaction）时，对方可以在 `receive/fallback` 回调里再次进入你。**

- 漏洞顺序（危险）：
  1) interaction：先转账（触发对方回调）
  2) effects：最后才更新余额/状态  
  → 回调重入时看到“旧状态”，可重复通过检查

- CEI 顺序（安全）：
  1) checks：先校验
  2) effects：**先更新状态（扣余额/置零）**
  3) interactions：最后才外部转账  
  → 回调重入时看到“新状态”，检查无法通过

---

## 9. `nonReentrant` 是关键字吗？`modifier` 是什么？为什么用 abstract contract 而不是 interface？

- `modifier` 是 Solidity 语法，用来给函数“包一层通用前后逻辑”
- `nonReentrant` **不是关键字**，只是一个自定义 modifier 名称（可改名）
- 典型防重入锁逻辑：
  - 进入时检查锁状态 → 上锁 → 执行函数体（`_;`）→ 解锁
- 为什么用 `abstract contract`：
  - 需要 **存储状态**（`_locked`）+ **实现 modifier 逻辑**
  - interface 只能声明函数签名，不能存状态、不能写 modifier 实现

---

## 10. Foundry：`vm.deal` / `vm.prank` / `vm.startPrank` 的常见误区

### 10.1 `vm.deal(addr, x)`
- 作用：把 `addr` 的 **ETH 余额直接设为 x**（不是累加）
- 只影响测试环境，用于快速造钱

### 10.2 `vm.prank(x)` vs `vm.startPrank(x)`
- `vm.prank(x)`：只影响 **下一次**外部调用的 `msg.sender`
- `vm.startPrank(x)`：影响后续 **多次**外部调用，直到 `vm.stopPrank()`

### 10.3 重要：prank 不会改变“合约内部调用”的 msg.sender
当你调用：
- EOA → `exp.seedAndAttack()`
- `exp`（合约）在内部再调用 `bank.deposit()` / `bank.withdraw()`

对 `bank` 来说：
- `msg.sender` 永远是 **exp 合约地址**
- 不是 attackerEOA  
这正是攻击需要的：因为重入回调发生在 **攻击合约的 receive** 里。

---

## 11. 你遇到的报错：`[FAIL: transfer failed]` 常见原因（重入示例的坑）

你见到的：
- `require(ok, "transfer failed")`

意味着：
- 外部转账调用返回 `ok=false`（收款方执行失败/回滚）

在重入示例里，常见坑是：
- 漏洞合约在回栈阶段执行 `balanceOf[msg.sender] -= amount;`
- 在 Solidity 0.8+ 下若多次扣减导致下溢，会 revert
- revert 会冒泡导致某层 `call{value: ...}` 失败 → `transfer failed`

更稳定的“最小银行重入”写法通常用 **withdrawAll：先转账后置零** 来复现（避免下溢影响复现稳定性）。

---

## 12. 一句话速记（面试/复习友好）

- `address(x).balance`：看 **ETH**（账户层）
- `token.balanceOf(x)`：看 **代币**（合约账本）
- `call{value: v}("")`：转 ETH + 空 calldata → 触发对方 `receive()`
- CEI：**先改状态再外部调用**
- `nonReentrant`：互斥锁，阻止同一交易内再次进入
- prank 只影响“顶层外部调用者”，不影响“合约内部调用的 msg.sender”

---
