# 2026-02-13 - D18 | ERC20 approve 竞态（“先改额度被夹”）+ 两种安全改法（先置 0 / increaseAllowance）

tags: [solidity, erc20, approve, allowance, race-condition, sandwich, foundry, security, audit]

## 背景 / 目标
`ERC20.approve(spender, value)` 是**覆盖式写入** allowance 的接口：它把 `allowance[owner][spender]` 直接设置为 `value`。  
当用户想把授权额度从 `old -> new`（且 **old != 0 且 new != 0**）时，如果 `spender` 观察到用户交易进入 mempool，就可能通过抢跑/夹击使得：
- 在用户 `approve(new)` 生效前先花掉 `old`
- 随后用户的 `approve(new)` 再上链
- `spender` 再花掉 `new`

结果：`spender` 总可花费 **old + new**（与用户“总共只想让花 new”的直觉相违背）。

**今日目标：**
1. 用 Foundry **复现** “先改额度被夹” 的可利用路径（old + new 被叠加）。
2. 写出两种**安全改法**并用测试验证：
   - 方案 A：`approve(0)` 再 `approve(new)`（两笔 tx）
   - 方案 B：使用 `increaseAllowance/decreaseAllowance`（差量更新）
3. 从**审计视角**列出检查点与修复建议。

---

## 漏洞机制（为什么会发生）
### 关键点：approve 是覆盖，不是“增量修改”
在很多实现里，`approve(spender, value)` 等价于：
```solidity
allowance[msg.sender][spender] = value; // 覆盖写入
```
这意味着：**用户把 100 改成 50** 并不是“减少 50”，而是“把值覆盖为 50”。

### 夹击/抢跑的本质：两笔交易的相对顺序可被操纵
现实链上：矿工/验证者、MEV、bot 等可能影响交易排序；测试里我们用“人为控制调用顺序”来模拟：
1) `approve(100)`  
2) `spender.transferFrom(..., 100)`（先花旧额度）  
3) `approve(50)`（覆盖写入新额度）  
4) `spender.transferFrom(..., 50)`（再花新额度）

最终 `spender` 花掉 150。

> 注：这不是“合约内部的线程并发”，而是**链上交易排序**导致的竞态（race condition）。

---

## 复现：先改额度被夹（old + new 叠加）

### 复现合约清单
- 漏洞版代币：`src/erc20/SimpleERC20ApproveRace.sol`
- spender 攻击/消费合约：`src/erc20/AllowanceSpender.sol`
- Foundry 测试：`test/vulns/ERC20ApproveRace.t.sol`

### 复现步骤（测试逻辑）
- Alice 先授权 spender：`approve(100)`
- Alice 想改小：`approve(50)`（注意：覆盖式写入）
- spender 在 `approve(50)` 之前先花掉旧额度 100
- Alice 的 `approve(50)` 上链后，spender 再花 50
- 断言 bob 最终收到 150

### 核心测试（片段）
```solidity
function test_race_approve_change_gets_sandwiched() public {
    vm.prank(alice);
    token.approve(address(spender), 100 ether);

    // ---- 夹击模拟：spender 在 approve(50) 之前先花掉旧额度 100 ----
    vm.prank(address(spender));
    spender.spendFrom(alice, bob, 100 ether);

    // Alice 的 approve(50) 才上链
    vm.prank(alice);
    token.approve(address(spender), 50 ether);

    // spender 再花 50
    vm.prank(address(spender));
    spender.spendFrom(alice, bob, 50 ether);

    assertEq(token.balanceOf(bob), 150 ether);
}
```

---

## 安全改法 A：先置 0 再设新额度（两笔 tx）
### 原则
当需要从 `old != 0` 改到 `new != 0` 时，推荐：
1) `approve(spender, 0)`  
2) 等确认后，再 `approve(spender, new)`

这样可避免“旧额度 + 新额度”被叠加的经典竞态路径。

### 风险说明（审计/使用提示）
- 如果 spender 能在 **清零 tx 确认前** 抢先花掉旧额度，那旧额度依然可能被用完（这属于“旧授权本来就给过”）。  
- 实务上常配合：更快确认、私有交易/MEV 保护、或者从 UX 上尽量避免“从非 0 改到非 0”。

### 测试验证要点
- 清零后，spender 不能再花旧额度
- 新额度设置后，spender 最多花 new

---

## 安全改法 B：increaseAllowance / decreaseAllowance（更推荐）
### 原则
不要用覆盖式 `approve(old->new)` 来表达“增减”，而应使用差量更新：
- 想增加：`increaseAllowance(spender, added)`
- 想减少：`decreaseAllowance(spender, subtracted)`

### 为什么更安全
差量更新会基于链上当前值计算。如果 spender 在中间抢跑消耗了一部分额度，链上 `cur` 已变化：
- `decreaseAllowance` 可能直接 revert（例如要减 50 但当前只剩 40），从而避免用户“误以为变成 50”的错误状态。
- 用户必须重新读取当前额度并重新计算，减少竞态下的意外叠加/失控。

---

## 如何运行（Foundry）
```bash
# 在你的 foundry 工程根目录（例如 labs/foundry-labs）
forge test --match-path test/vulns/ERC20ApproveRace.t.sol -vvv
```

---

## 审计视角检查清单（写给审计/安全测试）
### 1) 合约接口与实现
- [ ] 是否使用标准 `approve` 覆盖式写入？（多数 ERC20 都是）
- [ ] 项目是否提供 `increaseAllowance/decreaseAllowance`？是否在文档/前端引导使用？
- [ ] 是否在 `approve` 中加入“从非 0 改到非 0 必须先置 0”的限制？（不常见，但可选）
- [ ] 是否支持 `EIP-2612 permit`（签名授权，减少链上交互，改善 UX，可搭配 nonce/deadline）？

### 2) 前端与交互（很多问题发生在 UI/路由器交互）
- [ ] 前端是否允许用户直接把 allowance 从非 0 改到非 0？若允许，是否做 “先置 0 再设新值” 的流程？
- [ ] 是否存在 “无限授权（2**256-1）” 引导？是否提供 revoke/限额提示？
- [ ] 对 Router/DEX 等 spender：是否提示用户分场景授权（按次/按额度）？

### 3) 业务影响与利用面
- [ ] spender 是否可能是第三方合约/路由器（不可控）？
- [ ] 资产是否高价值、授权是否频繁修改？频繁修改更容易触发竞态
- [ ] 是否存在自动化脚本/机器人监听 mempool 并抢跑 `transferFrom` 的经济激励？

### 4) 修复建议（落地优先级）
- **P0（立刻可做）**：前端改成交互：从非 0 改到非 0 → 强制两步 `approve(0)` + `approve(new)`  
- **P1（更推荐）**：优先使用 `increaseAllowance/decreaseAllowance` 进行差量变更  
- **P2（更佳体验）**：支持 `permit`，减少链上批准步骤并加强 nonce/截止时间控制  
- **P3（安全教育）**：文档/提示明确“approve 竞态风险、无限授权风险、revoke 方法”

---

## 今日产出（建议你写到仓库 INDEX）
- 📄 文档：`docs/2026/02/2026-02-13-D18-ERC20-approve-race-condition.md`
- 📦 代码：
  - `src/erc20/SimpleERC20ApproveRace.sol`
  - `src/erc20/AllowanceSpender.sol`
- 🧪 测试：`test/vulns/ERC20ApproveRace.t.sol`
- 关键词：erc20 / approve / allowance / race-condition / sandwich / increaseAllowance / audit

---

## 复盘
- approve 竞态不是“合约内部并发”，而是交易排序导致的竞态。
- 覆盖式 `approve(old->new)` 在 `old!=0 && new!=0` 时风险最大。
- 修复策略优先级：**差量更新（increase/decrease） > 先置 0 再设新值 > 文档提示**。
