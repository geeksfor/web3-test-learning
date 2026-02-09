# D15 | Reentrancy（重入）最小银行：攻击 + 修复回归

tags: [solidity, security, reentrancy, foundry, cei, reentrancy-guard]

## 1. 漏洞一句话
在 `withdraw` 中 **先向外部地址转账（interaction）**，再 **更新内部余额（effect）**，攻击者可在 `receive/fallback` 中再次调用 `withdraw`，重复提款，直到资金池被掏空。

## 2. 影响
- 攻击者用少量存款作为“门票”，可把合约里其他用户的资金一起盗走
- 典型场景：Bank、Vault、Staking、AMM 的 withdraw/redeem、NFT/Token 的退款逻辑等

## 3. 复现条件
- 目标函数对外部地址 `call/transfer/send` 或调用不可信合约
- 状态更新（余额扣减、已领取标记）发生在外部调用之后
- 攻击者合约在 `receive/fallback` 中可再次进入目标函数

## 4. PoC 结构
- `MiniBankVuln`：脆弱银行（错误顺序）
- `ReentrancyAttacker`：攻击合约（receive 里重入）
- Foundry Test：先让 victim 存入资金池，再由 attacker 存入少量并攻击，断言 bank 余额为 0

## 5. 修复方案
### 5.1 CEI（Checks-Effects-Interactions）
- 先做检查（checks）
- 再更新状态（effects）：余额先扣
- 最后外部交互（interactions）：再转账

### 5.2 ReentrancyGuard（互斥锁）
- 进入函数时上锁，退出时解锁
- 同一笔交易的“再次进入”直接 revert
- 适合复杂流程/多外部调用/跨函数组合，但仍建议配合 CEI

## 6. 回归测试点
- Vulnerable：攻击成功，bank 余额归零，attacker 获利 > 初始存款
- CEI：攻击交易 revert 或无法继续提款，bank 余额不变
- Guard：第二次进入触发 REENTRANT，bank 余额不变

## 7. 如何运行
```bash
cd labs/foundry-labs
forge test --match-contract D15ReentrancyTest -vvv
## 8. 关键点
call{value:...}("") 会触发对方 receive/fallback，这就是重入入口

“外部调用”不仅是转账：token.transfer(...)、nft.safeTransferFrom(...)、任意对不可信合约的调用都可能引入重入

不要依赖 transfer(2300 gas) 作为防护（gas 规则与 EVM 环境变化会让这种假设不可靠）

flowchart TD
  %% ===== Vulnerable =====
  subgraph V["Vulnerable：withdraw 先转账后更新状态（可重入）"]
    V1[Attacker EOA 调用攻击合约 seedAndAttack()] --> V2[攻击合约存入 Bank.deposit(value=1 ETH)]
    V2 --> V3[攻击合约调用 Bank.withdraw(amount)]
    V3 --> V4[Bank 检查 balanceOf[attacker] >= amount]
    V4 --> V5[Bank 执行 msg.sender.call{value:amount}(&quot;&quot;)\n把 ETH 打给攻击合约]
    V5 --> V6[攻击合约 receive() 被触发]
    V6 --> V7{Bank 资金池还有钱?}
    V7 -- 是 --> V3
    V7 -- 否 --> V8[回到 Bank.withdraw 继续执行]
    V8 --> V9[Bank 最后才更新状态\nbalanceOf[attacker] -= amount / 或 balance=0]
    V9 --> V10[结果：可重复通过检查\n多次提款 → 资金池被掏空]
  end

  %% ===== CEI Fix =====
  subgraph C["CEI 修复：先更新状态，再外部转账（重入时检查失败）"]
    C1[Attacker 触发 Bank.withdraw] --> C2[Bank 检查余额]
    C2 --> C3[先 effects：扣减/清零 balanceOf[attacker]]
    C3 --> C4[再 interaction：call{value:amount}(&quot;&quot;)]
    C4 --> C5[攻击合约 receive() 尝试重入 withdraw]
    C5 --> C6[重入到 Bank.withdraw 再次检查余额]
    C6 --> C7{余额是否仍 >= amount?}
    C7 -- 否 --> C8[revert / 无法继续提款]
    C8 --> C9[结果：最多取回自己那份\n无法盗走资金池]
  end

  %% ===== Guard Fix =====
  subgraph G["ReentrancyGuard 修复：进入函数上锁，重入直接失败"]
    G1[Attacker 调用 Bank.withdraw] --> G2[nonReentrant: require(unlocked)]
    G2 --> G3[上锁 locked=2]
    G3 --> G4[执行 call{value:amount}(&quot;&quot;)]
    G4 --> G5[攻击合约 receive() 尝试重入 withdraw]
    G5 --> G6[再次进入 withdraw → nonReentrant 检查]
    G6 --> G7{locked==1?}
    G7 -- 否 --> G8[revert: REENTRANT]
    G8 --> G9[外层 withdraw 结束后解锁 locked=1]
    G9 --> G10[结果：同一交易内无法二次进入\n攻击链条被切断]
  end

