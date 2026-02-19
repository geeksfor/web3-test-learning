# 2026-02 学习索引（INDEX）

> 说明：本文件用于汇总 2026 年 02 月的每日学习文档，便于快速回顾与跳转。

## 目录

### 2026-02-01
- **D5 | Foundry Fuzz：随机 amount 的 transfer 后余额守恒（限制范围）+ VS Code 智能提示修复**  
  - 📄 文档：[`2026-02-01-D5-foundry-fuzz-transfer-balance-conservation.md`](./2026-02-01-D5-foundry-fuzz-transfer-balance-conservation.md)
  - 📦 代码：`labs/foundry-labs/src/SimpleERC20.sol`
  - 🧪 测试：`labs/foundry-labs/test/SimpleERC20.Fuzz.t.sol`  
  - 关键词：fuzz / bound / 余额守恒 / remappings.txt / IntelliSense
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --fuzz-runs 2000 --match-test testFuzz_transfer_balanceConservation -vvv
  ```

- **D5-2 | README + Coverage 初始盘点（待补覆盖率)**
- 📄 文档：[`2026-02-01-D5-2-readme-coverage.md`](./2026-02-01-D5-2-readme-coverage.md)

### 2026-02-03
- **D6 | Foundry Fuzz：D8：ERC721 测试框架（mint / ownerOf / balanceOf）+ fuzz + invariant**  
  - 📄 文档：[`2026-02-03-D6-ERC721-tests.md`](./2026-02-03-D6-ERC721-tests.md)
  - 📄 学习笔记：[`erc721-notes.md`](./erc721-notes.md)
  - 📦 代码：`labs/foundry-labs/src/erc721/SimpleERC721.sol`
  - 🧪 测试：`labs/foundry-labs/test/erc721/SimpleERC721.t.sol`  
  - 关键词：fuzz / erc721 / mint / balanceOf / ownerOf / invariant
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract SimpleERC721Test -vvv
  ```
- **D6 | ERC721 Transfer：transferFrom / safeTransferFrom（正常 + 未授权 revert）**  
  - 📄 文档：[`2026-02-04-D9-ERC721-transfer-safeTransfer.md`](./2026-02-04-D9-ERC721-transfer-safeTransfer.md)
  - 📄 学习笔记：[`erc721_erc20_foundry_notes.md`](./erc721_erc20_foundry_notes.md)
  - 📦 代码：`labs/foundry-labs/src/erc721/SimpleERC721.sol`
  - 🧪 测试：`labs/foundry-labs/test/erc721/SimpleERC721.auth.t.sol`  
  - 关键词：erc721 / transferFrom / safeTransferFrom / approve / operator / revert / receiver
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract SimpleERC721AuthTest -vvv
  ```
### 2026-02-04
- **D10 | ERC721 Approvals：approve / getApproved + setApprovalForAll / isApprovedForAll（正常 + revert + 转移后清空）**  
  - 📄 文档：[`2026-02-04-D9-ERC721-transfer-safeTransfer.md`](./2026-02-04-D9-ERC721-transfer-safeTransfer.md)
  - 📄 学习笔记：[`2026-02-05-D10-ERC721-approvals.md`](./2026-02-05-D10-ERC721-approvals.md)
  - 📦 代码：`labs/foundry-labs/src/erc721/SimpleERC721.sol`
  - 🧪 测试：`labs/foundry-labs/test/erc721/SimpleERC721.approvals.t.sol`  
  - 关键词：erc721 / approve / getApproved / setApprovalForAll / isApprovedForAll / operator / events / revert / clear-approval
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract SimpleERC721ApprovalsTest -vvv
  ```

### 2026-02-06
- **D11 | 权限模型：Ownable / AccessControl（错误示例 + 正确示例）测试集：未初始化 / 锁死 / 越权扩张**  
  - 📄 文档：[`2026-02-06-D11-Auth-Ownable-AccessControl.md`](./2026-02-06-D11-Auth-Ownable-AccessControl.md)
  - 📄 学习笔记：[`2026-02-AccessControl-Ownable-Foundry-Notes.md`](./2026-02-AccessControl-Ownable-Foundry-Notes.md)
  - 📦 代码：`labs/foundry-labs/src/auth/*.sol`
  - 🧪 测试：`labs/foundry-labs/test/auth/*.t.sol`  
  - 关键词：ownable / accesscontrol / MINTER_ROLE / DEFAULT_ADMIN_ROLE / grantRole / revokeRole / role-admin / lock / self-admin / privilege-escalation
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-path test/OpenZeppelinSimple/*.t.sol -vvv
  ```
### 2026-02-07
**D12 | Invariant 入门：ERC20 totalSupply == minted-burned（ghost state / Handler / trace 定位）**
- 📄 文档：[`2026-02-08-D12-ERC20-invariant-totalSupply.md`](./2026-02-08-D12-ERC20-invariant-totalSupply.md)
  - 📦 代码：`labs/foundry-labs/src/SimpleERC20.sol`
  - 🧪 测试：`labs/foundry-labs/test/erc20/SimpleERC20.invariant.t.sol`
  - 关键词：invariant / StdInvariant / handler / ghost state / mintedSum / burnedSum / trace / shrink
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract SimpleERC20InvariantTest -vvv --runs 500
  ```
### 2026-02-09
- **D15 | Reentrancy：最小银行（攻击合约 + 修复 CEI / ReentrancyGuard）回归**
  - 📄 文档：[`2026-02-09-D15-reentrancy-minibank.md`](./2026-02-09-D15-reentrancy-minibank.md)
  - 📄 学习笔记: [`D15-reentrancy-qa-notes.md`](./D15-reentrancy-qa-notes.md)]
  - 📦 漏洞：`labs/foundry-labs/src/vulns/D15_Reentrancy_Vuln.sol`
  - 💥 攻击：`labs/foundry-labs/src/vulns/D15_Reentrancy_Exploit.sol`
  - 🧪 测试：`labs/foundry-labs/test/vulns/D15_Reentrancy.t.sol`
  - 关键词：reentrancy / receive / fallback / CEI / nonReentrant / call{value:}
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract D15ReentrancyTest -vvv


### 2026-02-10
- **D16 | 权限缺陷：Missing Access Control（缺 onlyOwner/role）→ PoC → AccessControl 角色修复 → 回归**
  - 📄 文档：[`2026-02-10-D16-access-control.md`](./2026-02-10-D16-access-control.md)
  - 📦 漏洞合约：`labs/foundry-labs/src/vulns/AccessControlVuln.sol`
  - ✅ 修复合约：`labs/foundry-labs/src/vulns/AccessControlRolesFixed.sol`
  - ✅ 修复合约：`labs/foundry-labs/src/vulns/AccessControlFixed.sol`
  - 🧪 测试：`labs/foundry-labs/test/vulns/AccessControlD16Roles.t.sol`
  - 🧪 测试：`labs/foundry-labs/test/vulns/AccessControlD16.t.sol`
  - 关键词：access control / onlyRole / CONFIG_ROLE / FINANCE_ROLE / PAUSER_ROLE / PoC / regression
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-path test/vulns/AccessControlD16Roles.t.sol -vvv
  ```
  ### 2026-02-11
  - **D17 | 初始化漏洞（可升级/可初始化合约）：init 可被重复调用；攻击 + 修复（initializer）**  
  - 📄 文档：[`2026-02-11-D17-init-vuln-initializer.md`](./2026-02-11-D17-init-vuln-initializer.md)
  - 📦 代码：
    - `src/vulns/D17_BadInit.sol`
    - `src/vulns/D17_GoodInit.sol`
  - 🧪 测试：
    - `test/vulns/D17_InitVuln.t.sol`
    - `test/vulns/D17_GoodInitVuln.t.sol`
  - 关键词：upgradeable / initializer / reinitializer / _disableInitializers / takeover / proxy / OpenZeppelin
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-path test/vulns/D17_InitVuln.t.sol -vvv
  forge test --match-path test/vulns/D17_GoodInitVuln.t.sol -vvv
  ```
  ### 2026-02-12
  **D17（进阶）| Proxy / delegatecall / UUPS onlyProxy（贴近生产）**
  - 📄 文档：[`2026-02-12-D17-proxy-uups-onlyproxy-notes.md`](./2026-02-12-D17-proxy-uups-onlyproxy-notes.md)
  - 📦 代码（建议落位）：
    - `src/vulns/D17_UUPS_OZ.sol`（OZ-only UUPS 示例：initializer + _authorizeUpgrade + _disableInitializers）
    - `src/mini/SimpleProxy.sol`、`src/mini/MinimalImpl.sol`（最小 Proxy/Impl 便于理解 delegatecall，可选）
  - 🧪 测试（建议落位）：
    - `test/vulns/D17_OZ_UUPS_OnlyProxy.t.sol`（initializer onlyOnce + onlyProxy + upgrade 权限）
    - `test/mini/ProxyDelegatecall.t.sol`（delegatecall 上下文与 storage 归属验证，可选）
  - 关键词：proxy / delegatecall / storage collision / EIP-1967 / initializer / UUPS / onlyProxy / upgradeToAndCall / OZ 5.5
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs

  # 生产贴近：OZ-only UUPS（initializer + onlyProxy）
  forge test --match-contract D17_OZ_UUPS_OnlyProxy_Test -vvv

  # 原理验证：最小 proxy / delegatecall（可选）
  forge test --match-path test/mini/ProxyDelegatecall.t.sol -vvv
  ```
---

### 2026-02-13
- **D18 | ERC20 approve 竞态：演示“先改额度被夹” + 安全改法（先置 0 / increaseAllowance）**
  - 📄 文档：[`2026-02-13-D18-ERC20-approve-race-condition.md`](./2026-02-13-D18-ERC20-approve-race-condition.md)
  - 📦 代码：
    - `src/erc20/SimpleERC20ApproveRace.sol`
    - `src/erc20/AllowanceSpender.sol`
  - 🧪 测试：`test/vulns/ERC20ApproveRace.t.sol`
  - 关键词：erc20 / approve / allowance / race-condition / sandwich / increaseAllowance / audit
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-path test/vulns/ERC20ApproveRace.t.sol -vvv
  ```

  ### 2026-02-14
  - **D19 | 整数精度/舍入：Vault share 计算 + Fee 舍入导致可利用行为（含审计视角 & Q&A）**  
  - 📄 文档：[`2026-02-14-D19-Rounding-Precision-Fee-Arbitrage.md`](./2026-02-14-D19-Rounding-Precision-Fee-Arbitrage.md)  
  - 📦 代码：`test/vulns/D19_RoundingVault*.t.sol`，`test/vulns/D19_FeeRounding*.t.sol`（按你的实际文件名调整）  
  - 关键词：vault / shares / totalAssets / totalShares / donation / floor / ceil / mulDiv / dust / fee rounding / split
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-path test/vulns/D19_*.t.sol -vvv
  ```

### 2026-02-17
- **D22 | Oracle 操纵（简化版）：可控价格源导致借贷异常（操纵前后资产变化断言）**  
  - 📄 文档：[`2026-02-17-D22-Oracle-manipulation.md`](./2026-02-17-D22-Oracle-manipulation.md)  
  - 📦 代码：`src/vulns/D22_MockOracle.sol`, `src/vulns/D22_VulnerableLending.sol`, `src/vulns/D22_SimpleERC20.sol`  
  - 🧪 测试：`test/vulns/D22_OracleManipulation.t.sol`  
  - 关键词：oracle / manipulation / lending / ltv / spot vs twap / defi  
  - ▶️ 运行：
  ```bash
  forge test --match-path test/vulns/D22_OracleManipulation.t.sol -vvv
  ```

## 使用建议
- 每天新增一篇文档后，在本 INDEX 里追加一条记录（日期 + D# + 标题 + 关键词）
- 若你按「每月一个文件夹」组织：建议路径 `docs/2026/02/index.md`（或 `INDEX.md`），统一大小写，避免跨平台大小写差异问题

- **D23 | Flash Loan 影响：同一交易内操纵价格/余额导致可套利（Route A + Route B）**
  - 📄 文档：[`2026-02-17-D23-FlashLoan-impact-RouteA-RouteB.md`](./2026-02-17-D23-FlashLoan-impact-RouteA-RouteB.md)
  - 📦 Route A：`labs/foundry-labs/src/d23/*`
  - 🧪 Route A：`labs/foundry-labs/test/d23/D23_FlashLoanDonation.t.sol`
  - 📦 Route B：`labs/foundry-labs/src/d23b/*`
  - 🧪 Route B：`labs/foundry-labs/test/d23/D23_FlashLoanSpotOracle.t.sol`
  - 关键词：flash-loan / oracle / AMM / spot-price / donation / vault / lending / foundry
  - ▶️ 运行（Route B）：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract D23_FlashLoanSpotOracle_Test -vvv
  ```

- **D24 | Slippage 缺失：swap 没有 minOut（任意价格都成交）+ Sandwich 示例 + 修复（minOut + deadline）**  
  - 📄 文档：[`2026-02-18-D24-Slippage-NoMinOut-Sandwich-Fix.md`](./2026-02-18-D24-Slippage-NoMinOut-Sandwich-Fix.md)  
  - 📦 代码（建议路径）：`labs/foundry-labs/src/vulns/D24_SimpleAMM.sol`、`labs/foundry-labs/src/vulns/D24_SimpleERC20.sol`  
  - 🧪 测试（建议路径）：`labs/foundry-labs/test/vulns/D24_NoSlippageProtectionVuln.t.sol`、`labs/foundry-labs/test/vulns/D24_SlippageProtectionFixed.t.sol`  
  - 关键词：amm / slippage / minOut / deadline / sandwich / mev / expectRevert  
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract D24_ -vvv
  ```
  - **D25 | DoS（gas grief / 大循环）：数组无限增长导致关键函数不可用；“达到阈值后必失败”**  
  - 📄 文档：`2026-02-18-D25-DoS-gas-grief-unbounded-loop.md`
  - 📦 关键词：dos / gas griefing / unbounded loop / pagination / cursor / out-of-gas / foundry
  - ▶️ 运行：
  ```bash
  forge test --match-contract D25_GasGrief_Test -vvv
  ```

- **D26 | 时间依赖：block.timestamp 被滥用 + “矿工可操控窗口”测试（vm.warp）**  
  - 📄 文档：[`2026-02-19-D26-timestamp-dependency.md`](./2026-02-19-D26-timestamp-dependency.md)  
  - 📦 代码（建议）：`src/vulns/D26_TimestampWindowVuln.sol` / `src/vulns/D26_TimestampWindowFixed.sol`  
  - 🧪 测试（建议）：`test/vulns/D26_TimestampWindow.t.sol`  
  - 关键词：timestamp / time-dependency / boundary / slot / epoch / vm.warp  
  - ▶️ 运行：
  ```bash
  forge te

## D29 | 复习跨链消息模型：srcChainId/srcApp/nonce/payload/messageId；确定 mock 结构
- 📄 文档：[`2026-02-19-D29-crosschain-message-model-mock.md`](./2026-02-19-D29-crosschain-message-model-mock.md)
- 📦 合约建议：
  - `src/mocks/lz/ILZReceiver.sol`
  - `src/mocks/lz/MockLZEndpoint.sol`
  - `src/bridge/BridgeSender.sol`
  - `src/bridge/BridgeReceiver.sol`
- 🧪 测试建议：`test/bridge/D29_CrossChainMessageModel.t.sol`
- 关键词：crosschain / messageId / nonce / payload / trusted remote / replay / mock endpoint
- ▶️ 运行：
```bash
forge test --match-contract D29_CrossChainMessageModel_Test -vvv
```
