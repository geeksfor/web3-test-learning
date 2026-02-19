# 2026-02-20 - D32｜跨链消息重放防护：processed[messageId]=true + 回归测试

tags: [foundry, forge, solidity, bridge, replay-protection, security, testing]

## 背景 / 目标

跨链消息的常见流程是：

> 源链发送 payload（包含收款人/金额等） → 目标链接收端合约执行（mint/释放/记账）

风险点：**同一条消息被重复投递/重复执行（Replay）**，会导致重复 mint、重复释放或重复记账。

本日目标：

1. 在接收端合约加入**重放防护**：`processed[messageId] = true`
2. 写**回归测试**：第一次成功、第二次同 messageId 重放必须 revert，并断言**状态不变**（余额、totalSupply 等）

---

## 核心知识点（通俗版）

### 1) 什么是 messageId（为什么能防重放）

**messageId** 可以理解为“这条跨链消息的身份证”。

只要能保证：**同一条跨链语义消息在目标链对应的 messageId 恒定且唯一**，你就可以用它做去重：

- 首次处理：`processed[messageId] = true`
- 再次出现相同 messageId：直接 revert（拒绝重放）

### 2) messageId 常见构造方式

常见做法是对以下信息做哈希：

- `srcChainId`：源链 ID
- `srcApp`：源链发送合约地址（或发送端 app）
- `nonce`：源链递增序号（同一 srcApp 下单调递增）
- `payload`：消息内容（例如 `(to, amount)`）

示例：

```solidity
bytes32 messageId = keccak256(abi.encode(srcChainId, srcApp, nonce, payload));
```

这样“同一条消息”（同四元组）重复投递时，hash 一样 → 触发 `processed` 拒绝。

### 3) 为什么建议“先标记 processed，再执行业务”

推荐顺序：

1. 检查 `processed[messageId]`（若 true 则 revert）
2. **先写入** `processed[messageId] = true`
3. 再执行业务逻辑（mint/释放等）

原因：更符合 **CEI（Checks-Effects-Interactions）** 的思想，能降低回调/外部调用带来的二次进入风险。

---

## 实现步骤（落地流程）

### Step 1：在 Receiver 合约中增加 processed 映射

```solidity
mapping(bytes32 => bool) public processed;
```

### Step 2：计算 messageId + 重放检查

```solidity
bytes32 messageId = keccak256(abi.encode(srcChainId, srcApp, nonce, payload));
if (processed[messageId]) revert Replay(messageId);
processed[messageId] = true;
```

### Step 3：写回归测试

至少包含：

- ✅ `test_firstDelivery_mints_and_marksProcessed`
- ✅ `test_replay_sameMessage_reverts_and_stateUnchanged`
- （可选）`test_samePayload_differentNonce_shouldPass`
- （建议）`test_nonEndpointCaller_reverts`（防伪造入口）

---

## 关键代码（可直接复用）

> 说明：以下是最小可用结构，你可以按自己的 mock endpoint/receiver 命名调整函数签名。

### 合约：BridgeReceiverProtected.sol（示例）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMintable {
    function mint(address to, uint256 amount) external;
}

contract BridgeReceiverProtected {
    error NotEndpoint(address caller);
    error Replay(bytes32 messageId);

    address public immutable endpoint;
    IMintable public immutable token;

    mapping(bytes32 => bool) public processed;

    constructor(address _endpoint, IMintable _token) {
        endpoint = _endpoint;
        token = _token;
    }

    function lzReceive(
        uint32 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload
    ) external {
        if (msg.sender != endpoint) revert NotEndpoint(msg.sender);

        bytes32 messageId = keccak256(abi.encode(srcChainId, srcApp, nonce, payload));
        if (processed[messageId]) revert Replay(messageId);

        // ✅ 建议先标记再执行业务
        processed[messageId] = true;

        (address to, uint256 amount) = abi.decode(payload, (address, uint256));
        token.mint(to, amount);
    }
}
```

### 测试：BridgeReceiverProtected.t.sol（示例）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/bridge/BridgeReceiverProtected.sol";

contract SimpleMintableERC20 is IMintable {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }
}

contract BridgeReceiverProtectedTest is Test {
    BridgeReceiverProtected receiver;
    SimpleMintableERC20 token;

    address endpoint = address(0xE0P);
    address srcApp   = address(0xA11CE);
    address to       = address(0xB0B);

    uint32 srcChainId = 101;
    uint64 nonce = 1;

    function setUp() public {
        token = new SimpleMintableERC20();
        receiver = new BridgeReceiverProtected(endpoint, IMintable(address(token)));
    }

    function _payload(address _to, uint256 _amount) internal pure returns (bytes memory) {
        return abi.encode(_to, _amount);
    }

    function _messageId(uint32 _srcChainId, address _srcApp, uint64 _nonce, bytes memory _payloadBytes)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_srcChainId, _srcApp, _nonce, _payloadBytes));
    }

    function test_firstDelivery_mints_and_marksProcessed() public {
        uint256 amount = 100;
        bytes memory payload = _payload(to, amount);
        bytes32 messageId = _messageId(srcChainId, srcApp, nonce, payload);

        vm.prank(endpoint);
        receiver.lzReceive(srcChainId, srcApp, nonce, payload);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.totalSupply(), amount);
        assertTrue(receiver.processed(messageId));
    }

    function test_replay_sameMessage_reverts_and_stateUnchanged() public {
        uint256 amount = 100;
        bytes memory payload = _payload(to, amount);
        bytes32 messageId = _messageId(srcChainId, srcApp, nonce, payload);

        // first delivery
        vm.prank(endpoint);
        receiver.lzReceive(srcChainId, srcApp, nonce, payload);

        uint256 balBefore = token.balanceOf(to);
        uint256 supplyBefore = token.totalSupply();

        // replay
        vm.prank(endpoint);
        vm.expectRevert(abi.encodeWithSelector(BridgeReceiverProtected.Replay.selector, messageId));
        receiver.lzReceive(srcChainId, srcApp, nonce, payload);

        // state unchanged
        assertEq(token.balanceOf(to), balBefore);
        assertEq(token.totalSupply(), supplyBefore);
        assertTrue(receiver.processed(messageId));
    }

    function test_samePayload_differentNonce_shouldPass() public {
        bytes memory payload = _payload(to, 100);

        vm.prank(endpoint);
        receiver.lzReceive(srcChainId, srcApp, 1, payload);

        vm.prank(endpoint);
        receiver.lzReceive(srcChainId, srcApp, 2, payload);

        assertEq(token.balanceOf(to), 200);
        assertEq(token.totalSupply(), 200);
    }

    function test_nonEndpointCaller_reverts() public {
        bytes memory payload = _payload(to, 100);
        vm.expectRevert(abi.encodeWithSelector(BridgeReceiverProtected.NotEndpoint.selector, address(this)));
        receiver.lzReceive(srcChainId, srcApp, nonce, payload);
    }
}
```

---

## 审计视角（Checklist）

### A. 重放防护是否存在且正确
- [ ] 是否维护 `processed[messageId]`（或 nonce bitmap / 消息序列）？
- [ ] 是否在执行业务前检查 `processed`，重放必须 revert？
- [ ] 是否**先标记 processed 再执行业务**（更接近 CEI，抗回调/二次进入）？

### B. messageId 的唯一性与边界
- [ ] messageId 是否包含足够的唯一字段（至少 `srcChainId + srcApp + nonce`，建议再加 `payload`）？
- [ ] nonce 是否来自可信的 endpoint/桥逻辑（不能被任意指定）？
- [ ] 同一 srcApp 下 nonce 是否单调递增（避免重放窗口）？

### C. 入口认证与伪造风险
- [ ] 接收入口是否校验 `msg.sender == endpoint`（或可信执行层）？
- [ ] 是否能被任意 EOA/合约直接调用 receiver，伪造 mint？

### D. 失败与 DoS 风险
- [ ] 如果 endpoint 校验不严，攻击者可能提前“占位”某些 messageId → DoS
- [ ] 若业务逻辑可能 revert，是否会造成“已标记 processed 但业务失败”的一致性问题？
  - 常见策略：业务逻辑应尽量不引入不确定外部依赖；必要时设计可恢复流程（例如记录消息并允许管理员重试/补偿）

---

## 运行方式

```bash
cd labs/foundry-labs
forge test --match-contract BridgeReceiverProtectedTest -vvv
```

---

## 常见坑

1. **messageId 字段不全**：只用 payload 可能在不同 srcApp/不同链之间冲突。
2. **先 mint 后 processed**：遇到复杂回调/可重入场景更危险。
3. **未校验 endpoint**：任何人都能调用 receiver 伪造消息直接 mint（高危）。
4. **重放测试只写 expectRevert，不做状态不变断言**：回归不够强，容易漏掉“部分状态已改变”的 bug。

---

## 本日交付物清单（可对照打勾）

- [ ] Receiver 增加 `processed[messageId]`
- [ ] 第一次执行成功（mint/释放）
- [ ] 重放 revert（自定义错误含 messageId）
- [ ] 回归断言：余额、totalSupply、processed 状态不变
- [ ] 入口校验：非 endpoint 调用必须 revert
