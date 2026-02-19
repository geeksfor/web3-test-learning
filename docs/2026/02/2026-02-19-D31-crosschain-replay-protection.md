# 2026-02-19 - D31：重放同一消息（Replay）测试：expectRevert + 状态不变

tags: [foundry, solidity, crosschain, replay, messageId, testing, security]

## 背景 / 目标（通俗版）
跨链（或任意“消息驱动”的系统）里，一条消息如果被**重复执行**，就可能导致：
- 同一笔铸币/发放执行两次 → **双花 / 超发**
- 同一笔提现/记账执行两次 → **资产被重复转出**
- 状态机被重复推进 → **协议账本不一致**

因此接收端必须做到：  
> **同一条消息只能成功一次**；第二次“重放”必须 **revert**，并且关键状态（例如用户余额、totalSupply）**保持不变**。

---

## 关键知识点
### 1) 什么是“同一消息”
通常用一个唯一标识 `messageId` 表示消息身份。典型组成：
- `srcChainId`：来源链 ID
- `srcApp`：来源应用地址
- `nonce`：递增序号（防止重复）
- `payload`：消息内容（例如 `(to, amount)`）

计算方式常见为：
```solidity
bytes32 messageId = keccak256(abi.encode(srcChainId, srcApp, nonce, payload));
```

只要以上字段相同，`messageId` 就相同 → 这就是“同一条消息”。

### 2) 防重放的最小实现（Exactly-once / 幂等）
接收合约维护：
```solidity
mapping(bytes32 => bool) processed;
```

处理流程：
1. 先算出 `messageId`
2. 如果 `processed[messageId] == true` → `revert AlreadyProcessed(messageId)`
3. 否则先 `processed[messageId] = true`
4. 再执行业务逻辑（mint / transfer / 记账等）

> 先标记再执行：更稳健，能降低某些回调/重入类场景导致的“二次进入”风险。

### 3) Foundry 如何验证“重放必失败 + 状态不变”
- 用 `vm.expectRevert(...)` 断言回滚（revert）
- 用“前置快照”断言回滚后状态不变：
  - `balBefore = token.balanceOf(user)`
  - `supplyBefore = token.totalSupply()`
  - 重放调用后：`assertEq(balance, balBefore)`、`assertEq(supply, supplyBefore)`

---

## 实现步骤（可直接照做）
### Step 1：实现最小接收端（含 `messageId` + `processed`）
- 只允许 `endpoint` 调用（模拟真实跨链 endpoint）
- 计算 `messageId`
- 做防重放检查
- 解析 `payload` 并 mint

### Step 2：实现一个可 mint 的最小 Token
- `mint(to, amount)`
- `balanceOf`
- `totalSupply`

### Step 3：写测试用例
- 第一次调用成功：断言余额和 `totalSupply` 增加
- 第二次同参数重放：`expectRevert` + 断言余额与 `totalSupply` 不变

---

## 参考代码（最小可跑通）
> 你可以把它们放到你的仓库结构中，例如：  
> `src/vulns/D31_ReplayProtection/BridgeReceiver.sol`  
> `src/vulns/D31_ReplayProtection/SimpleMintableERC20.sol`  
> `test/vulns/D31_ReplayProtection.t.sol`

### A) Token：SimpleMintableERC20.sol
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract SimpleMintableERC20 {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}
```

### B) 接收端：BridgeReceiver.sol（直接引用具体 token 类型，最直观）
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./SimpleMintableERC20.sol";

contract BridgeReceiver {
    error OnlyEndpoint();
    error AlreadyProcessed(bytes32 messageId);

    address public immutable endpoint;
    SimpleMintableERC20 public immutable token;

    mapping(bytes32 => bool) public processed;

    constructor(address _endpoint, address _token) {
        endpoint = _endpoint;
        token = SimpleMintableERC20(_token);
    }

    function computeMessageId(
        uint16 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(srcChainId, srcApp, nonce, payload));
    }

    function receiveMessage(
        uint16 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload
    ) external {
        if (msg.sender != endpoint) revert OnlyEndpoint();

        bytes32 messageId = computeMessageId(srcChainId, srcApp, nonce, payload);
        if (processed[messageId]) revert AlreadyProcessed(messageId);

        // ✅ 先标记，再执行：更稳健
        processed[messageId] = true;

        (address to, uint256 amount) = abi.decode(payload, (address, uint256));
        token.mint(to, amount);
    }
}
```

### C) 测试：D31_ReplayProtection.t.sol
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleMintableERC20.sol";
import "../src/BridgeReceiver.sol";

contract D31_ReplayProtection_Test is Test {
    SimpleMintableERC20 token;
    BridgeReceiver receiver;

    address endpoint = address(0xE11P01NT);
    address user     = address(0xA11CE);
    address srcApp   = address(0xBEEF);

    uint16 srcChainId = 101;
    uint64 nonce      = 777;

    function setUp() public {
        token = new SimpleMintableERC20();
        receiver = new BridgeReceiver(endpoint, address(token));
    }

    function test_replay_same_message_reverts_and_state_unchanged() public {
        bytes memory payload = abi.encode(user, 100);

        // 1) 第一次：成功
        vm.prank(endpoint);
        receiver.receiveMessage(srcChainId, srcApp, nonce, payload);
        assertEq(token.balanceOf(user), 100);
        assertEq(token.totalSupply(), 100);

        // 2) 第二次：重放 -> 必须 revert，且状态不变
        uint256 balBefore = token.balanceOf(user);
        uint256 supplyBefore = token.totalSupply();

        bytes32 messageId = receiver.computeMessageId(srcChainId, srcApp, nonce, payload);

        vm.expectRevert(abi.encodeWithSelector(BridgeReceiver.AlreadyProcessed.selector, messageId));
        vm.prank(endpoint);
        receiver.receiveMessage(srcChainId, srcApp, nonce, payload);

        assertEq(token.balanceOf(user), balBefore);
        assertEq(token.totalSupply(), supplyBefore);
    }
}
```

### D) 运行
```bash
cd labs/foundry-labs
forge test --match-contract D31_ReplayProtection_Test -vvv
```

---

## 审计视角（Checklist）
### 防重放与消息身份
- [ ] `messageId` 是否包含足够字段（`srcChainId/srcApp/nonce/payload`）避免碰撞？
- [ ] 是否把 `payload` 纳入 `messageId`（否则同 nonce 可能被替换 payload 重放）？
- [ ] `nonce` 是否单调递增且与 `srcApp`/`srcChainId` 绑定？

### 权限与信任边界
- [ ] 入口函数是否 `onlyEndpoint`（防止任何人伪造跨链入口调用）？
- [ ] endpoint/relayer 的信任假设是否清晰（权限可否被替换/升级）？

### 状态更新顺序（抗重入/一致性）
- [ ] 是否“先写 `processed=true` 再执行业务逻辑”（更稳健）？
- [ ] 如果业务逻辑会外部调用（例如回调/transfer），是否存在重入导致二次处理风险？
- [ ] revert 时是否保证关键状态不变（余额、总量、记录表、计数器等）？

### 测试覆盖
- [ ] 覆盖：首次成功 + 重放失败
- [ ] 覆盖：重放失败时状态不变（余额、`totalSupply`）
- [ ] 覆盖：非 endpoint 调用应失败（可新增一条 `OnlyEndpoint` 测试）

---

## 今日产出清单
- ✅ 防重放（processed mapping）最小实现
- ✅ Foundry：`vm.expectRevert` + “状态不变”断言模板
- ✅ 可直接复用到后续跨链 mock / endpoint 场景

