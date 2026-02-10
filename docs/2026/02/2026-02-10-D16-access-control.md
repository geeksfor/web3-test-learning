# 2026-02-10 — D16 权限缺陷：Missing Access Control（缺 onlyOwner/role）→ PoC → 角色修复 → 回归

tags: [solidity, foundry, security, access-control, openzeppelin, audit]

> 今日目标：用一条“最小闭环”跑通权限漏洞的安全测试流程：  
> **先证明漏洞存在（未授权调用成功）→ 再用 AccessControl 角色分权修复 → 回归测试确保未授权被拦截且授权仍可用**。

---

## 1. 背景：什么是权限缺陷（Missing Access Control）

在合约中，一些**敏感函数**必须由管理员（owner / role）调用。如果这些函数**缺少访问控制**（如 `onlyOwner` 或 `onlyRole`），则任何人都能调用，造成：

- **资金损失**：改收款地址/提取资金/改费率导致“抽税”
- **服务不可用（DoS）**：恶意 `pause()` 导致用户无法交互
- **止损失效**：官方想暂停止损，攻击者可 `unpause()` 继续运行

---

## 2. 今日产出清单（Deliverables）

- ✅ 漏洞合约：`AccessControlVuln.sol`
- ✅ 修复合约（角色版）：`AccessControlRolesFixed.sol`
- ✅ 测试：
  - 漏洞 PoC：证明 attacker 能成功改配置/盗费/DoS
  - 修复回归：证明 attacker 被拦住（revert），合法角色能成功操作
- ✅ 本文档（便于复习 + 可做面试/审计作品集）

建议路径（可按你仓库实际调整）：

- 合约
  - `labs/foundry-labs/src/security/AccessControlVuln.sol`
  - `labs/foundry-labs/src/security/AccessControlRolesFixed.sol`
- 测试
  - `labs/foundry-labs/test/vulns/AccessControlD16Roles.t.sol`
- 文档
  - `docs/2026/02/2026-02-10-D16-access-control.md`

---

## 3. Step-by-step：详细操作步骤

### Step 0：建分支（建议）
```bash
git checkout -b d16-access-control-missing-guard
```

---

### Step 1：写“有漏洞”的合约（用于 PoC）

关键点：

- 提供敏感函数：`setTreasury / setFee / pause / unpause / withdrawFees`
- 故意**不加任何权限控制**
- 提供可观察后果：状态变量变化/余额变化/事件

（你今天使用的漏洞合约核心逻辑）
- `pay()` 计算 fee 并累计到 `feesAccrued`
- `withdrawFees()` 将累计 fee 打到 `treasury`
- 漏洞链路：**attacker setTreasury(attacker) → withdrawFees() 盗走手续费**

---

### Step 2：写“未授权调用成功”的 PoC 测试（漏洞证明）

PoC 测试的关键不是 `expectRevert`，而是**证明攻击成功**：

- treasury 被攻击者改成 attacker
- attacker 成功提走手续费（余额增加）
- paused 被攻击者打开，导致正常 pay revert（DoS）

运行：
```bash
cd labs/foundry-labs
forge test --match-path test/vulns/AccessControlD16Roles.t.sol -vvv
```

---

### Step 3：修复：用 AccessControl 角色分权（推荐审计/工程实践）

引入 OpenZeppelin `AccessControl`，定义 3 类角色（示例）：

- `CONFIG_ROLE`：改配置（`setTreasury / setFee`）
- `FINANCE_ROLE`：资金归集（`withdrawFees`）
- `PAUSER_ROLE`：紧急开关（`pause / unpause`）

构造函数中分配角色：
- `DEFAULT_ADMIN_ROLE` → admin（负责 grant/revoke 角色）
- 其他角色分别给 config/finance/pauser 账号

敏感函数用 `onlyRole(ROLE)` 保护。

---

### Step 4：回归测试（Regression）

回归测试要覆盖两类断言：

1) **未授权必须 revert**
- attacker 调用敏感函数 → revert
- 状态/余额保持不变

2) **授权仍可成功**
- config/finance/pauser 按职责调用 → 成功
- `pause` 生效后，`pay()` 应 revert

#### 重要坑：Foundry prank “没生效”导致错误的 msg.sender

你今天遇到的典型错误：
- 期望 revert 里 account 是 attacker
- 实际 revert 里 account 变成测试合约地址 `0x7FA...`

原因：
- `vm.prank(attacker)` 只影响**下一次外部调用**  
  如果中间被其它调用“吃掉”，真正的目标调用就用回默认 sender。

**解决方案（推荐）**：用 `vm.startPrank(attacker)`，更稳：

```solidity
vm.startPrank(attacker);
vm.expectRevert(...);
fixedR.setTreasury(attacker);
vm.stopPrank();
```

---

## 4. OpenZeppelin v5.5.0 的 expectRevert 写法（精准断言）

你确认 `openzeppelin-contracts` 版本是 **5.5.0**。

OZ v5 的 `onlyRole` 未授权错误，通常来自接口 `IAccessControl`：

```solidity
import "@openzeppelin/contracts/access/IAccessControl.sol";

vm.expectRevert(
  abi.encodeWithSelector(
    IAccessControl.AccessControlUnauthorizedAccount.selector,
    attacker,
    fixedR.CONFIG_ROLE()
  )
);
```

> 注意：很多情况下 **error 定义在 IAccessControl**，不是 `AccessControl.` 的 member。

---

## 5. 建议的测试结构（模板）

### 5.1 漏洞 PoC（未授权成功）
- `test_VULN_attackerCanStealFees_via_setTreasury_then_withdraw()`
- `test_VULN_attackerCanPause_DoS()`

### 5.2 修复回归（未授权被拦 + 授权可用）
- `test_FIXED_attackerCannotSetTreasury()`
- `test_FIXED_attackerCannotWithdrawFees()`
- `test_FIXED_attackerCannotPause()`
- `test_FIXED_configCanSetTreasuryAndFee()`
- `test_FIXED_financeCanWithdrawFees_toTreasury()`
- `test_FIXED_pauserCanPause_and_payReverts()`

---

## 6. 审计视角：知识点清单（Checklist）

下面这份清单建议你以后看到合约就按这个思路过一遍（非常“审计视角”）。

### 6.1 第一层：识别敏感入口（见到就重点盯）
- 资金相关：`withdraw/claim/transfer/skim/sweep`
- 收款地址：`setTreasury/setFeeRecipient/setReceiver`
- 参数配置：`setFee/setRate/setOracle/setRouter/setCollateralFactor`
- 紧急开关：`pause/unpause`
- 权限体系：`setAdmin/grantRole/revokeRole/transferOwnership`
- 可升级：`upgradeTo/upgradeToAndCall`（UUPS/Proxy）
- 铸销：`mint/burn`（尤其是 mint）

### 6.2 第二层：检查访问控制是否“存在且正确”
- 是否缺 guard（Missing Access Control）
- guard 是否写错（Incorrect Access Control）
  - role 写错
  - 判断对象写错（msg.sender vs tx.origin / 参数 vs 状态变量）
  - admin/owner 初始化写错
- 是否存在“权限升级通道”
  - 任意人可 `grantRole`
  - 任意人可 `transferOwnership`
  - 默认 admin 给了错误地址/零地址

### 6.3 第三层：关注业务后果（安全影响）
- 能否 **改钱的去向**（treasury/feeRecipient）
- 能否 **改钱的规则**（fee/rate/oracle）
- 能否 **直接转走钱**（withdraw/sweep）
- 能否 **停机/解禁**（pause/unpause）
- 是否能绕过止损与风控

### 6.4 第四层：测试与 PoC（审计报告式输出）
- “未授权调用成功”的 PoC：用断言证明结果（余额/状态/事件）
- 修复回归：
  - 未授权 revert（必要时精确匹配 error）
  - 授权仍可用（防止误伤）
- 事件校验（加分项）：`vm.expectEmit` 证明状态变化的证据链

---

## 7. 今日命令速记

```bash
cd labs/foundry-labs

# 跑单文件
forge test --match-path test/vulns/AccessControlD16Roles.t.sol -vvv

# 跑 vulns 目录
forge test --match-path test/vulns -vvv
```

---

## 8. 今日提交建议（commit message）

```bash
feat(security): D16 missing access control PoC + AccessControl roles fix + regression tests
```

---

## 9. 你今天真正掌握了什么（自评）

- 能识别“敏感函数 + 缺访问控制”这种高频漏洞
- 能写 PoC 测试证明“未授权调用成功”
- 能用 AccessControl 进行角色分权修复
- 能写回归测试验证修复有效（并解决 prank 相关坑）
