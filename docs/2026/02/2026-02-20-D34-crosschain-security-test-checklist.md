# 2026-02-20 - D34 | 跨链安全测试 Checklist（nonce / domain separation / endpoint 权限 / 重放表）

tags: [crosschain, security, testing, replay, nonce, domain-separation, endpoint, audit-checklist, foundry]

> 目标：把“跨链消息接收端（Receiver）”最常见、最致命的安全假设做成**可执行的测试清单**。你可以把本页当成：
> - ✅ 写测试时的逐条对照表
> - 🧾 审计视角的检查清单（审计报告里常见的发现点）
> - 🧪 回归测试模板（漏洞版 vs 修复版）

---

## 1. 威胁模型速记（为什么这些点重要）

跨链系统里，接收端通常信任：
1) 消息确实来自某条源链（srcChainId）  
2) 消息确实来自某个被授权的源应用（srcApp / srcSender）  
3) 消息只会被处理一次（anti-replay）  
4) 消息顺序/唯一性不会被攻击者利用（nonce / ordering）  

任何一个环节出错，都可能导致：**无限 mint、重复释放、跨域重放、假消息注入**。

---

## 2. Checklist 总览（写测试时先跑这一页）

### A. Nonce（唯一性 / 顺序性 / 可预测性）
- [ ] nonce 是否**单调递增**（per srcApp / per srcChain / per sender）？是否存在回退、复用？
- [ ] nonce 是否是**消息域的一部分**（参与 messageId / digest 计算）？
- [ ] nonce 的来源是否可信：是 endpoint 分配，还是应用自行传入？若应用传入是否可被操控？
- [ ] 是否存在 **nonce 竞争/重入**（同一交易或同一块内多次处理）导致重复成功？
- [ ] “跳号”是否允许？如果允许，是否会影响业务（比如必须按序解锁/释放）？
- [ ] 非法 nonce 输入（0、极大值、旧 nonce）是否都能正确 revert？

**建议测试用例**
- ✅ `test_nonce_included_in_messageId()`：同 payload，不同 nonce → messageId 必须不同
- ✅ `test_reject_old_or_reused_nonce()`：复用 nonce → 必须 revert（或失败且状态不变）
- ✅ `test_nonce_monotonic_per_domain()`：源 app/源链维度的 nonce 不互相污染

---

### B. Domain Separation（跨 app / 跨链域隔离）
> 核心：**同一份 payload** 在不同域（srcChainId/srcApp/dstChainId/dstApp/version）下，必须是不同的 messageId/digest。

- [ ] messageId 计算是否至少包含：`srcChainId + srcApp + nonce + payload`？
- [ ] 是否还应包含：`dstChainId / dstApp(receiver)`（避免跨目的域重放）？
- [ ] 是否包含 `version`（协议升级后避免旧消息在新逻辑里被接受）？
- [ ] 是否包含 `endpoint` 地址 / channelId（同链多 endpoint 场景）？
- [ ] 对于多路由/多桥支持：是否包含 bridgeId / laneId？

**建议测试用例**
- ✅ `test_domainSep_srcApp_changes_messageId()`：同 nonce/payload，换 srcApp → messageId 不同
- ✅ `test_domainSep_srcChain_changes_messageId()`：同 nonce/payload，换 srcChainId → messageId 不同
- ✅ `test_domainSep_dstApp_or_receiver_changes_messageId()`：同源域消息，换 receiver → 必须不被接受/或 messageId 不同
- ✅ `test_domainSep_version_changes_messageId()`：V1 与 V2 计算不同 → 不可互相重放

**常见审计发现**
- ❌ messageId 只用 `(nonce, payload)`，导致跨链/跨 app 可重放
- ❌ messageId 用 `abi.encodePacked` 拼接可变长字段导致碰撞（建议使用 `abi.encode`）

---

### C. Endpoint 权限（谁能投递消息）
> 核心：Receiver 只能接受来自**可信 endpoint** 的调用（或可信路由合约）。

- [ ] Receiver 的入口函数（如 `lzReceive`, `receiveMessage`, `handle`）是否 **onlyEndpoint**？
- [ ] endpoint 是否可升级/可更换？若可更换是否受严格权限控制（onlyOwner / timelock / governance）？
- [ ] endpoint 调用时传入的 `srcApp/srcAddress` 是否被验证（mapping allowlist）？
- [ ] 是否存在“任何人都能伪造 endpoint 参数”的路径（例如直接暴露 `processMessage`）？
- [ ] 对于链上验证（签名/证明）：验证是否覆盖到完整域（srcChainId/srcApp/nonce/payload）？

**建议测试用例**
- ✅ `test_onlyEndpoint_can_call_receive()`：非 endpoint 调用 → 必须 revert
- ✅ `test_endpoint_must_match_configured()`：更换 endpoint 前后行为正确；未授权更换必须 revert
- ✅ `test_srcApp_allowlist_enforced()`：伪造 srcApp → 必须 revert

**常见审计发现**
- ❌ 只校验 `msg.sender == endpoint`，但 endpoint 内部不校验 `srcApp`，导致任意应用伪造
- ❌ endpoint 更新函数未加 onlyOwner / role，导致被替换成恶意 endpoint

---

### D. 重放表（Anti-replay / processed[messageId]）
> 核心：每个 messageId **只能成功一次**；失败不能把状态推进到“已处理”。

- [ ] 是否有 `processed[messageId] = true` 的存储标记？
- [ ] 设置 processed 的时机是否正确：**检查通过后、状态变更前**还是**状态变更后**？（需要结合重入风险）
- [ ] 是否保证“失败不污染”：如果执行中 revert，processed 不应被置 true（除非你刻意做“失败也标记”策略）
- [ ] processed 的 key 是否就是**带 domain separation 的 messageId**？（别用裸 nonce）
- [ ] 是否考虑不同消息版本/不同链域的 processed 冲突？
- [ ] 是否有事件：`MessageProcessed(messageId, ...)` 便于监控与回放排查？

**建议测试用例**
- ✅ `test_replay_same_message_reverts_and_state_unchanged()`：重复投递同 messageId → revert + 余额/supply 不变
- ✅ `test_replay_after_partial_fail_does_not_brick()`：第一次因业务条件失败 → 后续条件满足应可成功（若设计如此）
- ✅ `test_processed_key_is_messageId_not_nonce()`：不同域同 nonce 不应互相阻塞

**常见审计发现**
- ❌ processed 标记在外部调用之后设置，存在重入重复处理窗口
- ❌ processed 使用 nonce 作为 key，导致跨 app/跨链域互相“撞车”

---

## 3. 推荐的 messageId 计算模板（审计友好）

> **推荐**使用 `abi.encode` 做结构化编码，并加上版本号/目的域（视业务选择）。

```solidity
// 示例：V1（源域隔离）
function computeMessageIdV1(
    uint16 srcChainId,
    address srcApp,
    uint64 nonce,
    bytes calldata payload
) public pure returns (bytes32) {
    return keccak256(abi.encode(
        "MSG_V1",
        srcChainId,
        srcApp,
        nonce,
        keccak256(payload)
    ));
}

// 示例：V2（加入目的域隔离，可选）
function computeMessageIdV2(
    uint16 srcChainId,
    address srcApp,
    uint16 dstChainId,
    address dstApp,     // receiver address
    uint64 nonce,
    bytes calldata payload
) public pure returns (bytes32) {
    return keccak256(abi.encode(
        "MSG_V2",
        srcChainId,
        srcApp,
        dstChainId,
        dstApp,
        nonce,
        keccak256(payload)
    ));
}
```

**审计点评**
- `keccak256(payload)`：避免 payload 很大时重复哈希开销，同时固定长度更清晰  
- `"MSG_V1"/"MSG_V2"`：版本域分离，升级时不互相重放  
- `dstChainId/dstApp`：防止“同源消息”被拿去喂给另一个 Receiver  

---

## 4. Foundry 测试模板（可直接改名复用）

> 下面是**结构模板**，你只需要把合约名/入口函数名对齐自己的项目即可。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

interface IReceiver {
    function receiveMessage(uint16 srcChainId, address srcApp, uint64 nonce, bytes calldata payload) external;
}

contract CrossChainSecurityChecklistTest is Test {
    address endpoint = address(0xE11D);
    address attacker = address(0xBEEF);

    address srcAppA = address(0xA11A);
    address srcAppB = address(0xB11B);
    uint16  srcChain1 = 101;
    uint16  srcChain2 = 102;

    IReceiver receiver;

    function setUp() public {
        // receiver = IReceiver(address(new BridgeReceiver(...)));
        // 在这里部署你的 Receiver，并把 endpoint 配好（如果 Receiver 里有 setEndpoint）
    }

    function _payload(address to, uint256 amount) internal pure returns (bytes memory) {
        return abi.encode(to, amount);
    }

    // --- C. onlyEndpoint ---
    function test_onlyEndpoint_can_call_receive() public {
        bytes memory payload = _payload(address(0xCAFE), 1);

        vm.expectRevert(); // 建议替换成具体错误
        vm.prank(attacker);
        receiver.receiveMessage(srcChain1, srcAppA, 1, payload);
    }

    // --- B. domain separation ---
    function test_domainSep_srcApp_changes_messageId_behavior() public {
        bytes memory payload = _payload(address(0xCAFE), 1);

        // 假设 endpoint 代为调用
        vm.prank(endpoint);
        receiver.receiveMessage(srcChain1, srcAppA, 1, payload);

        // 用相同 nonce/payload，但换 srcApp，应该是“不同 messageId”，因此不应被当作重放
        vm.prank(endpoint);
        receiver.receiveMessage(srcChain1, srcAppB, 1, payload);

        // 这里建议断言：两次都成功，且状态变化符合预期（如 mint 两次给同一人）
        // 或者：如果业务不允许同 payload 在不同 srcApp 出现，也应明确 revert 原因。
    }

    // --- D. replay ---
    function test_replay_same_message_reverts_and_state_unchanged() public {
        bytes memory payload = _payload(address(0xCAFE), 1);

        // 1st delivery succeeds
        vm.prank(endpoint);
        receiver.receiveMessage(srcChain1, srcAppA, 1, payload);

        // 2nd delivery should revert and not change state
        vm.expectRevert(); // 具体错误：AlreadyProcessed(messageId)
        vm.prank(endpoint);
        receiver.receiveMessage(srcChain1, srcAppA, 1, payload);

        // 建议加：余额 / totalSupply / 关键 mapping 不变断言
    }

    // --- A. nonce reuse ---
    function test_reject_reused_nonce_same_domain() public {
        bytes memory payload1 = _payload(address(0xCAFE), 1);
        bytes memory payload2 = _payload(address(0xCAFE), 2);

        vm.prank(endpoint);
        receiver.receiveMessage(srcChain1, srcAppA, 7, payload1);

        // 同域复用 nonce（如果你的协议要求 nonce 唯一），应当 revert
        vm.expectRevert();
        vm.prank(endpoint);
        receiver.receiveMessage(srcChain1, srcAppA, 7, payload2);
    }
}
```

---

## 5. 审计视角 Checklist（报告里常用的“结论句”）

你在写审计笔记时，可以直接复用这些句式：

- **[High] Cross-domain replay**：messageId 计算缺少 srcChainId/srcApp/dstApp/version，导致攻击者可跨链/跨应用重放消息，造成重复 mint/释放。  
- **[High] Missing endpoint authorization**：接收入口缺少 onlyEndpoint，任意地址可调用伪造跨链消息，导致资产被盗。  
- **[Medium] Improper replay protection ordering**：processed 标记设置时机不当，存在重入窗口或失败污染，可能导致重复处理或 DoS。  
- **[Medium] Nonce misuse**：nonce 不唯一/可回退/不在签名域内，可能导致消息覆盖、重放或顺序假设被破坏。  
- **[Low/Info] Weak encoding**：使用 abi.encodePacked 拼接变长字段，存在潜在碰撞风险；建议改为 abi.encode 并加版本前缀。  

---

## 6. 建议的分支 / Commit（D34）

### 分支名（建议）
- `d34-crosschain-security-checklist`

### commit 信息（建议）
- `docs(d34): add cross-chain security testing checklist (nonce, domain separation, endpoint auth, replay)`

---

## 7. 下一步（可选加强项）
- 将 checklist “可执行化”：为每个条目建立 `test_*`，并在 CI 中强制跑
- 生成 `messageId` 结构图（src/dst/version/nonce/payload）用于 README
- 对接真实桥接框架（LayerZero / Wormhole / Axelar）时，把“endpoint 验证点”落到具体接口与错误码上
