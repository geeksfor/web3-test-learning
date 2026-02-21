# 从测试角度讲签名安全（面试笔记）

> 这篇笔记适合面试时“口述讲清楚 + 作品集落地展示”。核心思路：把签名安全拆成可测试的安全性质（security properties），用 Foundry 写成可复现 PoC + 回归测试闭环。

---

## 1. 我怎么理解“签名安全”

在链上系统里，**签名 = 离线授权凭证**。  
交易签名（发交易）和业务签名（EIP-712/EIP-191/permit/meta-tx）本质都是“证明某个私钥同意某件事”，区别在于：

- **交易签名**：同意“执行一笔交易”（包含 nonce/gas/chainId/to/value/data）  
- **业务签名**：同意“某个意图”（比如给 spender 授权、跨链消息确认、代付交易授权）

测试视角要抓住一句话：

> **签名一旦泄露，攻击者可以在链上无限次提交它。**  
> 所以安全目标是：**签名只能在正确的域里、在正确的时间窗里、被用一次、对正确的参数生效。**

---

## 2. 威胁模型：攻击者能做什么（Threat Model）

我在做签名相关测试时，会先把威胁模型写出来（面试可直接讲）：

- 能拿到签名：钓鱼前端、日志泄露、离线签名复用、社工
- 能重放：同一签名重复提交
- 能跨域重放：换链 / 换合约 / 换业务域（App、模块、功能）继续用
- 能夹击：MEV front-run/back-run 放大风险（尤其 permit/approve）
- 能卡边界：deadline 最后一秒 / timestamp 轻微操控

---

## 3. 我用“用例矩阵”覆盖签名安全（5 大必测块）

我通常把签名安全拆成 5 个必测块（面试回答很清晰）：

### 3.1 Replay（重放）——必须“一次性”

**风险**：没有 nonce 或 nonce 不消耗 → 同签名可重复执行。  

**测试点（断言）**：
- 同一份签名提交两次：**第二次必须 revert**
- 第二次失败时：关键状态不变化（余额、totalSupply、授权额度、processed 标记等）

**常见修复**：
- nonce 递增（EIP-2612/元交易）
- 或 `used[hash]=true`（消息类/跨链类）

---

### 3.2 Deadline（时间窗）——必须“可过期”

**风险**：没有 deadline 或不校验 → 永不过期签名。  

**测试点（断言）**：
- `deadline < block.timestamp` 必须 revert
- 边界：`deadline == block.timestamp` 是允许还是拒绝？要写清楚并测出来
- 使用 `vm.warp()` / `roll()` 做时间边界覆盖

**常见修复**：强制校验 deadline，并统一比较符号（`<` vs `<=`）。

---

### 3.3 Domain Separation（域隔离）——必须“绑链 + 绑合约”

**风险**：签名没有绑定 chainId / contract address → 换链/换合约仍能用。  

**测试点（断言）**：
- 同一签名在 **不同 chainId** 下应失败（Foundry 可用 `vm.chainId()` 或 fork）
- 同一签名在 **不同合约地址**（重新部署一份）下应失败

**常见修复**：EIP-712 domain 中包含：
- `chainId`
- `verifyingContract`
- `name` / `version`（避免跨应用/跨版本复用）

---

### 3.4 Message Binding（参数绑定）——必须“绑对参数”

**风险**：签名只绑定部分参数，攻击者替换未绑定字段。  
例：只签了 amount，没签 recipient → 攻击者改收款人。

**测试点（断言）**：
- “缺字段攻击”：构造签名时故意少签一个字段，然后在链上换字段应能成功（证明漏洞）
- “全字段修复”：修复后同样攻击必须失败

**常见修复**：typed data / structHash 中把业务关键字段全部纳入。

---

### 3.5 Encoding（哈希组装）——必须“抗碰撞”

**风险**：`abi.encodePacked` 组 hash 可能产生拼接碰撞/类型混淆。  

**测试点（断言）**：
- 给出一组能碰撞的输入（或至少证明 packed 存在潜在碰撞面）
- 修复后（`abi.encode` + typehash）同输入不再碰撞

**常见修复**：结构化数据统一用 `abi.encode`，EIP-712 用 typehash + structHash。

---

## 4. 落地方法：我如何把它写成“作品集级”测试闭环

我会把每个签名主题做成一套“可展示、可回归”的结构：

- `Vuln.sol`：错误实现（故意少 nonce / 少 domain / 少 deadline）
- `Fixed.sol`：修复实现
- `*.t.sol`：
  - 正常路径（签名正确 → 成功）
  - 攻击路径（重放/跨域/过期/换字段 → 失败）
  - 回归断言（状态不变 + 明确错误类型）

面试时可以强调：

> 我写的不只是“功能测试”，而是“安全性质测试”：证明攻击可行、证明修复有效、证明不会回归。

---

## 5. 三个典型例子（讲起来最加分）

### 5.1 Nonce Replay（同签名重放）

**演示逻辑**：没有 nonce → 同签名执行两次都成功。  
**修复**：nonce 递增，第二次 revert。  
**关键断言**：第二次失败时余额/状态不变。

---

### 5.2 Domain Separation（换链/换合约仍能用）

**演示逻辑**：签名哈希不含 chainId/contract → 在另一链/另一部署仍能用。  
**修复**：EIP-712 domain 绑定 chainId + verifyingContract。  
**关键断言**：换 chainId 或换合约地址后同签名必失败。

---

### 5.3 EIP-2612 Permit（批准类签名）

我会测 4 件事：
- permit 成功后 allowance 正确
- nonce 递增
- deadline 生效
- 重放失败

并说明 permit 的价值（面试常问）：

> permit 让用户不需要先发 approve 交易（省一笔交易），但也因此更需要严格的 nonce/deadline/domain。

---

## 6. 面试 30 秒总结版（建议背下来）

> 签名安全从测试角度就是五件事：  
> **一次性（nonce/used）、可过期（deadline）、有域隔离（chainId+contract+name/version）、参数绑定完整、哈希组装抗碰撞。**  
> 我会把每个点都写成 vuln→attack test→fix→regression 的闭环，并用 Foundry 的 warp/chainId/prank 等手段覆盖边界与重放场景。

---

## 7. 加分项：我额外会关注的点

- **签名可撤销吗**：nonce 自然递增不可撤销，但可以有“失效策略/提高 nonce”等手段
- **错误信息可观测**：自定义 error 便于测试精确断言
- **链下签名一致性**：前端 typed data 与合约 typehash 完全一致（字段顺序/类型）
- **事件/状态一致性**：permit 成功应 emit Approval；失败不应有副作用
- **MEV 竞争条件**：approve/permit 的竞态风险（如“先改额度被夹”）

