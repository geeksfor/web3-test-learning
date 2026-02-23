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

- **D30 | Normal Cross-Chain Happy Path（Burn/Mint or Lock/Release）**
  - 📄 文档：[`2026-02-19-D30-NormalCrossChain-BurnMint.md`](./2026-02-19-D30-NormalCrossChain-BurnMint.md)
  - 📦 示例代码：`src/bridge/*`（MockEndpoint + Bridge + Token）
  - 🧪 测试：`test/bridge/D30_NormalCrossChain_BurnMint.t.sol`
  - 关键词：crosschain / endpoint / lzReceive / trustedSrcApp / abi.encode / abi.decode / happy-path
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract D30_NormalCrossChain_BurnMint_Test -vvv
  ```

 **D31 | 重放同一消息（Replay）防护测试：expectRevert + 状态不变（余额、totalSupply）**  
  - 📄 文档：[`2026-02-19-D31-crosschain-replay-protection.md`](./2026-02-19-D31-crosschain-replay-protection.md)
  - 关键词：replay / messageId / processed / expectRevert / state-unchanged
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract D31_ReplayProtection_Test -vvv
  ```

  - **D32 | 跨链消息重放防护：processed[messageId]=true + 回归测试**  
  - 📄 文档：[`2026-02-20-D32-replay-protection-processed.md`](./2026-02-20-D32-replay-protection-processed.md)  
  - 📦 代码（参考路径）：`src/bridge/BridgeReceiverProtected.sol`  
  - 🧪 测试（参考路径）：`test/bridge/BridgeReceiverProtected.t.sol`  
  - 关键词：bridge / replay-protection / messageId / nonce / processed / expectRevert / state-unchanged  
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract BridgeReceiverProtectedTest -vvv
  ```
  - **D33 | 跨 app 重放 / 跨链域隔离（messageId 含 srcApp/dstApp/chainId）**
  - 📄 文档：[`2026-02-20-D33-crossapp-replay-domain-separation.md`](./2026-02-20-D33-crossapp-replay-domain-separation.md)
  - 📦 代码（建议路径）：`src/bridge/MessageIdLib.sol`、`src/bridge/BridgeReceiver.sol`
  - 🧪 测试（建议路径）：`test/bridge/D33_DomainSeparation_Replay.t.sol`
  - 关键词：replay / domain-separation / messageId / srcApp / dstApp / chainId
  - ▶️ 运行：
  ```bash
  forge test --match-contract D33_DomainSeparation_Replay_Test -vvv
  ```
  - **D34 | 跨链安全测试 Checklist（nonce、domain separation、endpoint 权限、重放表）**
  - 📄 文档：[`2026-02-20-D34-crosschain-security-test-checklist.md`](./2026-02-20-D34-crosschain-security-test-checklist.md)
  - 关键词：crosschain / security / nonce / domain-separation / endpoint / replay / processed
  - ▶️ 运行（若你把测试模板落地到 test/ 目录）：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract CrossChainSecurityChecklistTest -vvv
  ```

  - **D36 | EIP-712 基础：domain separator、typed data；最小 verify 合约 + 正常验签测试**  
  - 📄 文档：[`2026-02-20-D36-EIP712-basics-min-verify.md`](./2026-02-20-D36-EIP712-basics-min-verify.md)  
  - 📦 代码：`labs/foundry-labs/src/eip712/D36_MinEIP712Verifier.sol`  
  - 🧪 测试：`labs/foundry-labs/test/eip712/D36_MinEIP712Verifier.t.sol`  
  - 关键词：eip712 / domainSeparator / typedData / typehash / digest / ecrecover / ecdsa / nonce / deadline  
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract D36_MinEIP712Verifier_Test -vvv
  ```
  - **D37 | Nonce 重放：不带 nonce 的错误实现 → 同签名可重复；攻击测试 + 修复回归（2026-02-20）**
  - 📄 文档：[`2026-02-20-D37-nonce-replay.md`](./2026-02-20-D37-nonce-replay.md)
  - 📦 合约：`src/vulns/D37_NonceReplayVuln.sol` / `src/vulns/D37_NonceReplayFixed.sol`
  - 🧪 测试：`test/vulns/D37_NonceReplay.t.sol`
  - 关键词：replay / nonce / signature / ECDSA / MessageHashUtils / custom error
  - ▶️ 运行：
    ```bash
    cd labs/foundry-labs
    forge test --match-contract D37_NonceReplay_Test -vvv
    ```
  - **D38 | 域隔离：deadline/chainId/contract address（换链/换合约重放示例）**
  - 📄 文档：[`2026-02-21-D38-domain-separation-deadline-chainid-contract.md`](./2026-02-21-D38-domain-separation-deadline-chainid-contract.md)
  - 📦 代码：
    - `src/vulns/D38_DomainSeparationBad.sol`
    - `src/fixed/D38_DomainSeparationGood.sol`
  - 🧪 测试：`test/vulns/D38_DomainSeparation.t.sol`
  - 关键词：deadline / chainId / address(this) / domain separation / replay / ecrecover / r,s,v
  - ▶️ 运行：
  ```bash
  forge test --match-contract D38_DomainSeparation_Test -vvv
  ```
  - **D39 | EIP-2612 permit：nonce / deadline + Foundry 测试（OZ ERC20Permit）**  
  - 📄 文档：[`2026-02-21-D39-EIP2612-permit-nonce-deadline.md`](./2026-02-21-D39-EIP2612-permit-nonce-deadline.md)  
  - 📦 代码：`labs/foundry-labs/src/erc20/PermitERC20.sol`  
  - 🧪 测试：`labs/foundry-labs/test/erc20/PermitERC20.permit.t.sol`  
  - 关键词：eip2612 / permit / eip712 / nonce / deadline / replay / openzeppelin  
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract PermitERC20_PermitTest -vvv
  ```
  - **D40 | 参数注入：签名内容与执行内容不一致（to/amount 未纳入签名）**  
  - 📄 文档：[`2026-02-21-D40-ParamInjection-signature-mismatch.md`](./2026-02-21-D40-ParamInjection-signature-mismatch.md)
  - 📦 代码：`labs/foundry-labs/src/vulns/D40_ParamInjectionVuln.sol` + `labs/foundry-labs/src/fixed/D40_ParamInjectionFixed.sol`
  - 🧪 测试：`labs/foundry-labs/test/vulns/D40_ParamInjection.t.sol`
  - 关键词：parameter injection / intent mismatch / to&amount signed / nonce / deadline / domain separation
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract D40_ParamInjection_Test -vvv
  ```

  - **D43 | 最小 AMM（x*y=k）+ Swap 基本正确性（含审计视角）**
  - 📄 文档：`2026-02-21-D43-Minimal-AMM-XYK-swap-correctness.md`
  - 📦 代码（建议路径）：
    - `labs/foundry-labs/src/amm/SimpleAMMXYK.sol`
    - `labs/foundry-labs/src/tokens/SimpleERC20.sol`
  - 🧪 测试：`labs/foundry-labs/test/amm/D43_SimpleAMMXYK.t.sol`
  - 关键词：amm / dex / xyk / constant product / swap / slippage / minOut / uint112 / rounding
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract D43_SimpleAMMXYK_Test -vvv
  ```

  - **D44 | Slippage / minOut：没有 minOut 的风险测试（先红测）+ 修复回归**
  - 📄 文档：`docs/2026/02/2026-02-21-D44-slippage-minout.md`
  - 📦 代码：
    - `labs/foundry-labs/src/vulns/D44_SlippageNoMinOut.sol`
    - `labs/foundry-labs/src/fixes/D44_SlippageWithMinOut.sol`
  - 🧪 测试：
    - `labs/foundry-labs/test/vulns/D44_SlippageNoMinOut.t.sol`
    - `labs/foundry-labs/test/fixes/D44_SlippageWithMinOut.t.sol`
  - 关键词：amm / x*y=k / slippage / minOut / sandwich / mev / deadline / regression
  - ▶️ 运行：
    ```bash
    cd labs/foundry-labs
    forge test --match-path test/vulns/D44_SlippageNoMinOut.t.sol -vvv
    forge test --match-path test/fixes/D44_SlippageWithMinOut.t.sol -vvv
    ```

  - **D45 | 价格操纵：小池子/低流动性造成价格偏移；TWAP 修复（spot vs TWAP）**
  - 📄 文档：`docs/2026/02/2026-02-22-D45-price-manipulation-twap.md`
  - 📦 代码建议路径：
    - `labs/foundry-labs/src/amm/SimpleAMMXYK.sol`
    - `labs/foundry-labs/src/amm/SimpleAMMXYK_TWAP.sol`
    - `labs/foundry-labs/src/vulns/D45_SpotOracleLendingVuln.sol`
    - `labs/foundry-labs/src/fixed/D45_SpotOracleLendingFixed_TWAP.sol`
  - 🧪 测试：
    - `labs/foundry-labs/test/vulns/D45_PriceManipulation.t.sol`
    - `labs/foundry-labs/test/vulns/D45_PriceManipulation_Fixed.t.sol`
  - 关键词：price manipulation / low liquidity / spot oracle / TWAP / cumulative price / vm.warp
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract D45_PriceManipulation_Test -vvv
  forge test --match-contract D45_PriceManipulation_Fixed_Test -vvv
  ```

## 2026-02-22

- **D46 | MEV/夹子（Sandwich）简化复现：先交易改变价格再执行 victim；断言 victim 实际成交恶化（并给出 minOut+deadline 修复）**
  - 📄 学习文档：`2026-02-22-D46-MEV-Sandwich.md`
  - 🧪 测试：`test/vulns/D46_MEVSandwich.t.sol`
  - 📦 合约：`src/vulns/D46_MEVSandwich.sol`
  - 关键词：MEV / sandwich / front-run / back-run / mempool / slippage / minOut / deadline
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract D46_MEVSandwich_Test -vvv
  ```

  - **D47 | Invariant：k 不应下降（考虑 fee 时的变化规则）**
  - 📄 文档：`2026-02-22-D47-KInvariant-k-not-decrease.md`
  - 📦 关键词：AMM / x*y=k / invariant / StdInvariant / handler / fee-on-input / rounding
  - 🧪 测试：`test/vulns/D47_KInvariant.t.sol`
  - ▶️ 运行：
    ```bash
    cd labs/foundry-labs
    forge test --match-contract D47_KInvariant_Test -vvv
    ```

  ## D50（Fork 测试）
- **D50：Foundry Fork 测试入门（createSelectFork + 固定区块）**  
  - 文件：`docs/2026/02/D50_Foundry_Fork_Test_createSelectFork.md`  
  - 关键词：fork / createSelectFork / pinned block / RPC / stateRoot / 可复现测试

- **D51**：`docs/2026/02/D51_ReadOnlyVerification_UniswapV2.md`
  - 只读验证概念与不变量思维
  - mainnet fork 用法（latest vs 固定区块）
  - 如何定位 Pair 地址（Factory.getPair）
  - Uniswap V2 Pair 常见健康检查断言
  - 今日问答汇总：reserve 同步、emit/view、接口标准性、fork 全局状态

- **D52 借贷场景：抵押率边界 / 清算触发（简化模型）**
  - 文档：`docs/2026/02/D52_Lending_CollateralBoundary_Liquidation.md`
  - 关键点：LTV vs LT、边界符号（> / >=）、WAD 单位换算、清算（repay→seize + bonus）、closeFactor、调试日志（emit log / console2 / event）
  - 标签：`[lending] [ltv] [liquidation] [oracle] [wad] [foundry]`

- **D53**：Oracle 更新频率 / 价格跳变 —— 更新前后清算条件变化测试  
  - 文档：`D53-oracle-update-frequency.md`  
  - 关键词：oracle / heartbeat / stale price / price jump / liquidation / TWAP / circuit breaker

## D54：Vault share 小额存取款舍入（Rounding）边界回归

- 主题：ERC4626 / Vault share↔asset 换算、整数除法取整、donation 扭曲比例、小额边界吞资产
- 产出：
  - 学习文档：`D54_vault-share-rounding.md`
  - 示例代码：
    - `src/D54_VaultRounding.sol`（vuln + fixed）
    - `test/vulns/D54_VaultRounding.t.sol`（复现 + 回归）
- 关键断言：
  - donation 后小额 deposit 在漏洞版会“收资产但不给 share”
  - 修复版必须 revert（ZeroShares），避免吞资产
  - 正常比例下小额 deposit 不被误伤

### 关联审计点（Checklist 速记）
- shares/assets 是否可能为 0？
- totalAssets 是否受 donation 影响？
- deposit/mint 与 withdraw/redeem 是否都有最小输出保护？
- rounding 策略是否一致、是否可被套利或 DoS？
