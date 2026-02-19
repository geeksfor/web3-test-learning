# 2026-02-19 - D29 跨链消息模型复习：srcChainId / srcApp / nonce / payload / messageId + Mock 结构确认

tags: [foundry, solidity, crosschain, layerzero, message, replay, mock, security, testing]

## 背景 / 目标

今天是 **D29（复习 + 基建）**：把跨链消息“最小模型”彻底复盘清楚，并把你项目里的 **Mock 结构（Endpoint / Sender / Receiver）** 固化为可复用基建。

你今天要能回答两类问题：

1) **字段含义**：`srcChainId/srcApp/nonce/payload/messageId` 分别代表什么、为什么需要它们  
2) **Mock 职责**：谁负责路由？谁负责鉴权？谁负责去重？（以及测试里如何覆盖）

> D29 本质不是“漏洞日”，而是跨链相关漏洞学习之前的 **基础设施整理**。后续 D30+ 才更适合进入 `vulns/`（vuln vs fixed 对照）。

---

## 跨链消息模型（通俗理解：快递单 + 包裹）

把一次跨链消息当作一张“快递单 + 包裹”：

- **srcChainId**：发货地（从哪条链发出）
- **srcApp**：发货人（源链上哪个应用/合约发出）
- **nonce**：这位发货人发出的第 N 单（防止“同一发货人重复单号”）
- **payload**：包裹内容（目标链要执行的数据，例如给某人记账 / mint）
- **messageId**：快递单的“唯一编号”（通常是上述字段 + payload 做哈希）

一个常见的 messageId 计算方式：

```solidity
bytes32 messageId = keccak256(abi.encode(srcChainId, srcApp, nonce, payload));
```

### 为什么一定要这几项？

- `srcChainId + srcApp`：用于判断消息“来自哪里、来自谁”，防伪造来源（否则攻击者可伪造发件方）
- `nonce`：每个发件方的递增序号，用于唯一性/顺序性（不同协议对“是否必须顺序处理”要求不同）
- `payload`：实际业务数据（目标链要执行什么）
- `messageId`：全局唯一指纹，用于 **去重 / 防重放**（Replay protection）

---

## Mock 结构确认：三方职责（Endpoint / Sender / Receiver）

### 1) Endpoint（邮局/路由器）
职责：
- 维护 `outboundNonce[srcApp][dstChainId]++`
- 负责把消息从源链“寄出”到目标链“投递队列”
- 在目标链投递时 **由 endpoint 调用 receiver.lzReceive(...)**  
  让 receiver 可用 `msg.sender == endpoint` 做第一道鉴权

### 2) Sender（发件应用/源合约）
职责：
- 构造 `payload`
- 调用 `endpoint.send(dstChainId, dstApp, payload)`
- 通常 nonce 不由 sender 自己维护，而由 endpoint 统一生成更贴近真实协议

### 3) Receiver（收件应用/目标合约）
职责（审计重点）：
1. **鉴权**：`require(msg.sender == endpoint)`
2. **来源校验**：校验 `srcChainId + srcApp` 在白名单（trusted remote）
3. **去重**：`processed[messageId]` 防重放
4. **执行业务**：`abi.decode(payload, ...)` 并执行 mint/credit/execute

---

## 目录与归档建议（回答：代码放哪？）

**建议把 D29 代码当作“可复用基建/示例”，不要塞进 `vulns/`：**

- 合约：
  - `src/mocks/lz/ILZReceiver.sol`
  - `src/mocks/lz/MockLZEndpoint.sol`
  - `src/bridge/BridgeSender.sol`
  - `src/bridge/BridgeReceiver.sol`

- 测试：
  - `test/bridge/D29_CrossChainMessageModel.t.sol`

> 当你做“漏洞 vs 修复”对照（比如重放漏洞）时，再放到：
> - `src/vulns/Dxx_*.sol`
> - `src/fixed/Dxx_*.sol`
> - `test/vulns/Dxx_*.t.sol`

---

## 关键实现（可直接用）：MockLZEndpoint（推荐“传字段”，避免 struct 跨合约参数坑）

下面版本专门规避你今天遇到的报错/坑：  
- remote 用 `address` 存  
- 投递队列用 `Packet[] inbox`  
- **跨合约 push 传字段**（避免 `struct` + `bytes` 的 ABI/可见性问题）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../mocks/lz/ILZReceiver.sol";

contract MockLZEndpoint {
    uint16 public immutable chainId;

    // dstChainId => endpoint address on dst
    mapping(uint16 => address) public remotes;

    // srcApp => dstChainId => nonce
    mapping(address => mapping(uint16 => uint64)) public outboundNonce;

    struct Packet {
        uint16 srcChainId;
        address srcApp;
        address dstApp;
        uint64 nonce;
        bytes payload;
        bytes32 messageId;
    }

    Packet[] public inbox;

    constructor(uint16 _chainId) {
        chainId = _chainId;
    }

    function setRemote(uint16 dstChainId, address dstEndpoint) external {
        remotes[dstChainId] = dstEndpoint;
    }

    function send(uint16 dstChainId, address dstApp, bytes calldata payload) external {
        uint64 n = ++outboundNonce[msg.sender][dstChainId];
        bytes32 mid = keccak256(abi.encode(chainId, msg.sender, n, payload));

        address dstEp = remotes[dstChainId];
        require(dstEp != address(0), "no remote");

        MockLZEndpoint(dstEp).pushToInboxFields(
            chainId,
            msg.sender,
            dstApp,
            n,
            payload,
            mid
        );
    }

    function pushToInboxFields(
        uint16 srcChainId_,
        address srcApp_,
        address dstApp_,
        uint64 nonce_,
        bytes calldata payload_,
        bytes32 messageId_
    ) external {
        inbox.push(Packet({
            srcChainId: srcChainId_,
            srcApp: srcApp_,
            dstApp: dstApp_,
            nonce: nonce_,
            payload: payload_,
            messageId: messageId_
        }));
    }

    function inboxLength() external view returns (uint256) {
        return inbox.length;
    }

    function deliverNext(uint256 idx) external {
        Packet memory p = inbox[idx];
        ILZReceiver(p.dstApp).lzReceive(p.srcChainId, p.srcApp, p.nonce, p.payload, p.messageId);
    }
}
```

---

## Receiver（审计重点）：鉴权 + 白名单 + messageId 去重

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../mocks/lz/ILZReceiver.sol";

contract BridgeReceiver is ILZReceiver {
    error NotEndpoint();
    error UntrustedSource(uint16 srcChainId, address srcApp);
    error AlreadyProcessed(bytes32 messageId);

    address public immutable endpoint;

    mapping(uint16 => mapping(address => bool)) public trusted;
    mapping(bytes32 => bool) public processed;

    event Received(uint16 srcChainId, address srcApp, uint64 nonce, bytes32 messageId, address to, uint256 amount);

    constructor(address _endpoint) {
        endpoint = _endpoint;
    }

    function setTrusted(uint16 srcChainId, address srcApp, bool ok) external {
        // demo：省略权限控制。真实项目应 onlyOwner / role + event
        trusted[srcChainId][srcApp] = ok;
    }

    function lzReceive(
        uint16 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload,
        bytes32 messageId
    ) external override {
        if (msg.sender != endpoint) revert NotEndpoint();
        if (!trusted[srcChainId][srcApp]) revert UntrustedSource(srcChainId, srcApp);
        if (processed[messageId]) revert AlreadyProcessed(messageId);

        processed[messageId] = true;

        // 业务演示：解码 payload（见下文 abi.decode 解释）
        (address to, uint256 amount) = abi.decode(payload, (address, uint256));

        emit Received(srcChainId, srcApp, nonce, messageId, to, amount);
    }
}
```

---

## Sender：构造 payload 并发送

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../mocks/lz/MockLZEndpoint.sol";

contract BridgeSender {
    MockLZEndpoint public immutable endpoint;

    constructor(MockLZEndpoint _endpoint) {
        endpoint = _endpoint;
    }

    function bridge(uint16 dstChainId, address dstApp, address to, uint256 amount) external {
        bytes memory payload = abi.encode(to, amount);
        endpoint.send(dstChainId, dstApp, payload);
    }
}
```

---

## Foundry 测试要覆盖的 3 件事（D29 复习重点）

1. **endpoint 鉴权**：只有 endpoint 能调用 `lzReceive`  
2. **trusted 来源校验**：`srcChainId + srcApp` 不可信要 revert  
3. **messageId 去重**：同一包重复投递要 revert（重放攻击防护）

测试骨架：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/mocks/lz/MockLZEndpoint.sol";
import "../src/bridge/BridgeSender.sol";
import "../src/bridge/BridgeReceiver.sol";

contract D29_CrossChainMessageModel_Test is Test {
    MockLZEndpoint epA;
    MockLZEndpoint epB;

    BridgeSender senderA;
    BridgeReceiver receiverB;

    uint16 constant CHAIN_A = 101;
    uint16 constant CHAIN_B = 102;

    address user = address(0xA11CE);

    function setUp() public {
        epA = new MockLZEndpoint(CHAIN_A);
        epB = new MockLZEndpoint(CHAIN_B);

        epA.setRemote(CHAIN_B, address(epB));
        epB.setRemote(CHAIN_A, address(epA));

        senderA = new BridgeSender(epA);
        receiverB = new BridgeReceiver(address(epB));

        receiverB.setTrusted(CHAIN_A, address(senderA), true);
    }

    function test_deliver_ok_and_processed() public {
        senderA.bridge(CHAIN_B, address(receiverB), user, 100);
        assertEq(epB.inboxLength(), 1);

        epB.deliverNext(0);
        // 可扩展：验证 receiverB.processed(messageId) 为 true（需要 getter 或重算 messageId）
    }

    function test_replay_same_packet_reverts() public {
        senderA.bridge(CHAIN_B, address(receiverB), user, 100);
        epB.deliverNext(0);

        bytes32 mid = keccak256(abi.encode(CHAIN_A, address(senderA), uint64(1), abi.encode(user, uint256(100))));

        vm.expectRevert(abi.encodeWithSelector(BridgeReceiver.AlreadyProcessed.selector, mid));
        epB.deliverNext(0);
    }

    function test_untrusted_source_reverts() public {
        receiverB.setTrusted(CHAIN_A, address(senderA), false);

        senderA.bridge(CHAIN_B, address(receiverB), user, 100);

        vm.expectRevert(abi.encodeWithSelector(BridgeReceiver.UntrustedSource.selector, CHAIN_A, address(senderA)));
        epB.deliverNext(0);
    }
}
```

---

## 今日提问汇总（Q&A）

### Q1：上面代码是否放到同漏洞不同的文件夹下？
建议 **D29 代码不放在 vulns**，而放在 `mocks/` + `bridge/` + `test/bridge/`。  
只有当你要做“重放漏洞 vuln vs fixed”对照时，才进入 `vulns/`。

### Q2：分支名称建议？
推荐：`d29-crosschain-message-mock`  
备选：`d29-crosschain-message-model` / `d29-bridge-mock-endpoint`

### Q3：Member "pushToInbox" not found ... 怎么修？
核心是“类型/可见性/struct 传参”三类坑。
推荐修法：remote 用 `address` 存，跨合约 push 用 **传字段**，并确保函数是 `external/public`。  
本文件提供的 `pushToInboxFields(...)` 版本就是为此准备的。

### Q4：`(address to, uint256 amount) = abi.decode(payload, (address, uint256));` 是什么写法？为什么 abi.decode 里有 `(address, uint256)`？
这是 **元组解构赋值 + ABI 解码**：

- `payload` 只是 `bytes`，Solidity 不知道里面是什么结构；
- `abi.decode(payload, (address, uint256))` 的第二个参数是“**类型描述（元组类型）**”，告诉编译器按什么顺序/类型解码；
- 左边 `(address to, uint256 amount)` 是把解码得到的两个值分别赋给变量。

必须满足：
```solidity
bytes memory payload = abi.encode(to, amount);
(address to2, uint256 amount2) = abi.decode(payload, (address, uint256));
```

---

## 审计视角 Checklist（建议你贴到后续跨链相关日更里）

- [ ] `lzReceive` **只能**由 endpoint 调用（`msg.sender == endpoint`）
- [ ] 同时校验 `srcChainId + srcApp`（只校验一个不够）
- [ ] `messageId/nonce` 去重防重放（重复必须 revert，且无副作用）
- [ ] payload 解码类型/顺序必须与 encode 一致（避免 decode 错误或 revert）
- [ ] `setTrusted`/endpoint 配置必须有权限控制 + 事件（防止配置被劫持）

---

## 今日完成清单（可复制到每日打卡）

- [x] 复盘字段：srcChainId / srcApp / nonce / payload / messageId 的含义与必要性  
- [x] 明确 Mock 职责：Endpoint 路由 + 生成 nonce；Receiver 鉴权 + 白名单 + 去重；Sender 构造 payload  
- [x] 固化可用 MockEndpoint（推荐传字段版本）  
- [x] 写 3 类测试：鉴权 / 来源校验 / 重放去重  
- [x] 回答今日提问并沉淀到文档

---

## 运行命令（示例）

```bash
forge test --match-contract D29_CrossChainMessageModel_Test -vvv
```
