# 2026-02-20 - D33：跨 app 重放 / 跨链域隔离（Domain Separation）测试

tags: [foundry, solidity, bridge, cross-chain, replay, security, domain-separation]

## 背景 / 目标

跨链消息通常是：源链发消息 → 目标链接收 → 执行业务（mint / 释放 / 记账等）。

**重放攻击（Replay）**的核心风险：同一条消息被再次投递，导致目标链重复执行（例如重复 mint）。

今天 D33 的目标是用测试把安全边界写死：

- ✅ **同域重放必须失败**
- ✅ **跨 app / 跨链必须隔离**：`messageId` 必须包含 **srcApp / dstApp / chainId**（至少 srcChainId + dstChainId 或固定 dstChainId 为本链；以及 dstApp=接收合约本身）
- ✅ 给出可复用的 `messageId` 计算规则，并在测试里验证“改变域信息 → messageId 一定变化”

---

## 核心知识点（通俗理解）

### 1) 什么是重放（Replay）

接收端常见写法：

1. 计算 `messageId`
2. `processed[messageId] == false` 才允许继续
3. 执行后 `processed[messageId] = true`

这样同一条消息第二次来，就会被挡住。

### 2) 为什么需要“域隔离”（Domain Separation）

如果 `messageId` 只用 `nonce/payload` 或字段不完整，可能出现：

- **跨 app 串域 DoS（误伤）**：AppA 处理过的消息 id，导致 AppB 的合法消息被误判为重放
- **跨 receiver 串域干扰**：同一条消息被投递到不同接收合约（dstApp 不同），如果 id 不含 dstApp，可能互相影响

因此 `messageId` 必须绑定消息“来自哪里、要到哪里”，常见最小集合：

- `srcChainId`
- `srcApp`
- `dstChainId`（或固定为本链）
- `dstApp`（通常就是接收合约地址 `address(this)`）
- `nonce`
- `payloadHash`（建议用 `keccak256(payload)`）

---

## 推荐实现：MessageId 计算规则

### 规则（建议）

```solidity
messageId = keccak256(abi.encode(
  "MSG_V1",
  srcChainId,
  srcApp,
  dstChainId,
  dstApp,
  nonce,
  keccak256(payload)
));
```

### 为什么要加 `"MSG_V1"`？

`"MSG_V1"` 是一个 **固定前缀 / 版本标签（domain separator）**：

- 防止你项目中别的 hash 规则（订单ID、签名ID、别的跨链模块）与 messageId “意外撞车”
- 便于未来升级：`MSG_V1` → `MSG_V2`（字段变化也不会互相混淆）

> `"MSG_V1"` 不是必须，但属于非常推荐的工程/安全实践。

---

## 参考代码（可直接落地）

> 你可以把以下文件放到类似路径：
- `src/bridge/MessageIdLib.sol`
- `src/bridge/BridgeReceiver.sol`
- `test/bridge/D33_DomainSeparation_Replay.t.sol`

### 1) `src/bridge/MessageIdLib.sol`

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library MessageIdLib {
    function compute(
        uint16 srcChainId,
        address srcApp,
        uint16 dstChainId,
        address dstApp,
        uint64 nonce,
        bytes memory payload
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "MSG_V1",
                srcChainId,
                srcApp,
                dstChainId,
                dstApp,
                nonce,
                keccak256(payload)
            )
        );
    }
}
```

### 2) `src/bridge/BridgeReceiver.sol`（示例：mint 模式）

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MessageIdLib} from "./MessageIdLib.sol";

interface IMintable {
    function mint(address to, uint256 amount) external;
}

contract BridgeReceiver {
    error Replay(bytes32 messageId);

    mapping(bytes32 => bool) public processed;

    uint16 public immutable dstChainId;
    IMintable public immutable token;

    constructor(uint16 _dstChainId, IMintable _token) {
        dstChainId = _dstChainId;
        token = _token;
    }

    // 模拟 Endpoint 的投递入口
    function lzReceive(
        uint16 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload
    ) external {
        bytes32 mid = MessageIdLib.compute(
            srcChainId,
            srcApp,
            dstChainId,
            address(this),
            nonce,
            payload
        );

        if (processed[mid]) revert Replay(mid);
        processed[mid] = true; // ✅ 先标记，后执行（CEI）

        (address to, uint256 amount) = abi.decode(payload, (address, uint256));
        token.mint(to, amount);
    }
}
```

### 3) `test/bridge/D33_DomainSeparation_Replay.t.sol`

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {BridgeReceiver} from "../src/bridge/BridgeReceiver.sol";
import {MessageIdLib} from "../src/bridge/MessageIdLib.sol";

contract SimpleMintableERC20 {
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
}

contract D33_DomainSeparation_Replay_Test is Test {
    SimpleMintableERC20 token;
    BridgeReceiver receiver;

    uint16 constant DST_CHAIN = 101;
    address alice = address(0xA11CE);

    function setUp() public {
        token = new SimpleMintableERC20();

        // ✅ 推荐写法：先转 address 再转 interface（最通用）
        receiver = new BridgeReceiver(DST_CHAIN, IMintable(address(token)));
    }

    function _payload(address to, uint256 amount) internal pure returns (bytes memory) {
        return abi.encode(to, amount);
    }

    /// 1) D33 核心：messageId 必须包含 srcApp/dstApp/chainId → 改任意一项都应变化
    function test_messageId_must_include_srcApp_dstApp_chainId() public view {
        uint16 srcChainId = 100;
        address srcAppA = address(0xAAA1);
        address srcAppB = address(0xAAA2);
        uint64 nonce = 1;
        bytes memory payload = _payload(alice, 100);

        bytes32 idA = MessageIdLib.compute(srcChainId, srcAppA, DST_CHAIN, address(receiver), nonce, payload);

        // 改 srcApp → 必须变化
        bytes32 idSrcAppChanged =
            MessageIdLib.compute(srcChainId, srcAppB, DST_CHAIN, address(receiver), nonce, payload);
        assertTrue(idA != idSrcAppChanged);

        // 改 dstApp → 必须变化
        bytes32 idDstAppChanged =
            MessageIdLib.compute(srcChainId, srcAppA, DST_CHAIN, address(0xBEEF), nonce, payload);
        assertTrue(idA != idDstAppChanged);

        // 改 chainId（src 或 dst 任意一侧）→ 必须变化
        bytes32 idSrcChainChanged =
            MessageIdLib.compute(uint16(999), srcAppA, DST_CHAIN, address(receiver), nonce, payload);
        assertTrue(idA != idSrcChainChanged);

        bytes32 idDstChainChanged =
            MessageIdLib.compute(srcChainId, srcAppA, uint16(202), address(receiver), nonce, payload);
        assertTrue(idA != idDstChainChanged);
    }

    /// 2) 同域重放：第二次必须 revert，且状态不变
    function test_replay_same_domain_reverts() public {
        uint16 srcChainId = 100;
        address srcApp = address(0xAAA1);
        uint64 nonce = 7;
        bytes memory payload = _payload(alice, 123);

        receiver.lzReceive(srcChainId, srcApp, nonce, payload);
        assertEq(token.balanceOf(alice), 123);

        bytes32 mid = MessageIdLib.compute(srcChainId, srcApp, DST_CHAIN, address(receiver), nonce, payload);
        vm.expectRevert(abi.encodeWithSelector(BridgeReceiver.Replay.selector, mid));
        receiver.lzReceive(srcChainId, srcApp, nonce, payload);

        assertEq(token.balanceOf(alice), 123);
    }

    /// 3) 跨 app：srcApp 不同 → 不应互相影响（不应误判 replay）
    function test_crossApp_domainIsolation_not_mark_replay() public {
        uint16 srcChainId = 100;
        address srcAppA = address(0xAAA1);
        address srcAppB = address(0xAAA2);

        uint64 nonce = 1;
        bytes memory payload = _payload(alice, 10);

        receiver.lzReceive(srcChainId, srcAppA, nonce, payload);
        receiver.lzReceive(srcChainId, srcAppB, nonce, payload);

        assertEq(token.balanceOf(alice), 20);
    }

    /// 4) 跨链：srcChainId 不同 → 不应互相影响
    function test_crossChain_domainIsolation_not_mark_replay() public {
        address srcApp = address(0xAAA1);
        uint64 nonce = 1;
        bytes memory payload = _payload(alice, 10);

        receiver.lzReceive(uint16(100), srcApp, nonce, payload);
        receiver.lzReceive(uint16(200), srcApp, nonce, payload);

        assertEq(token.balanceOf(alice), 20);
    }
}
```

---

## Q&A（把你今天问的都收口进来）

### Q1：以前的 `computeMessageId(srcChainId, srcApp, nonce, payload)` 是否已解决跨 app / 跨链域隔离？
**结论：部分解决，但不完整。**

- ✅ 如果实现把 `srcChainId` 编进 hash：能隔离不同源链
- ✅ 如果实现把 `srcApp` 编进 hash：能隔离不同源 app
- ❌ 但缺少 **dstApp / dstChainId** 时，无法隔离“目标域”，可能造成跨 receiver/多环境/升级并行时的串域干扰（通常表现为误判重放 DoS）

> D33 要求 **messageId 必须包含 srcApp/dstApp/chainId**，所以旧版签名不满足（缺 dstApp/ dstChainId）。

### Q2：`library` 是什么写法？不是 `interface` 吗？
- `library`：工具函数集合（可复用的实现逻辑），适合放纯计算（如 messageId hash）
- `interface`：只声明函数签名，用来调用别的合约（如 `IMintable.mint(...)`）

### Q3：`MSG_V1` 是什么？
`"MSG_V1"` 是固定的**版本前缀 / 域分隔符**，用来：
- 防止不同模块的 hash 规则撞车
- 未来升级时区分 V1/V2（字段变化也不混淆）

### Q4：`receiver = new BridgeReceiver(DST_CHAIN, IMintable(token));` 为什么不对？
常见原因：**Solidity 对“具体合约类型 → 接口类型”的显式转换有限制**。

最通用写法：

```solidity
receiver = new BridgeReceiver(DST_CHAIN, IMintable(address(token)));
```

更优雅的写法是让 token 合约显式实现接口：

```solidity
contract SimpleMintableERC20 is IMintable {
  function mint(address to, uint256 amount) external override { ... }
}
```

然后直接 `new BridgeReceiver(DST_CHAIN, token)` 即可。

---

## 审计视角 Checklist（今日重点）

- [ ] `messageId` 是否包含域信息：`srcChainId`, `srcApp`, `dstApp`（建议再带 `dstChainId`）
- [ ] 是否包含 `nonce`（同域内去重关键）
- [ ] `payload` 是否先 hash（`keccak256(payload)`）再参与编码，减少可变长编码歧义
- [ ] 是否有固定前缀/版本（如 `"MSG_V1"`）避免跨模块撞车、便于升级
- [ ] Replay guard 是否符合 CEI：先 `processed=true` 再执行 mint/转账等外部调用
- [ ] revert 错误是否包含 `messageId`（便于排查与告警）

---

## 运行命令（建议写进你的仓库）

```bash
# 仅跑 D33
forge test --match-contract D33_DomainSeparation_Replay_Test -vvv
```

---

## 今日产出清单（你可以对照落库）

- 📄 文档：`docs/2026/02/2026-02-20-D33-crossapp-replay-domain-separation.md`
- 📦 代码：`src/bridge/MessageIdLib.sol`、`src/bridge/BridgeReceiver.sol`
- 🧪 测试：`test/bridge/D33_DomainSeparation_Replay.t.sol`

