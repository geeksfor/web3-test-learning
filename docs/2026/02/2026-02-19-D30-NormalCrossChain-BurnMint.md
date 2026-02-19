# 2026-02-19 - D30：正常一次跨链（Burn/Mint 或 Lock/Release）Happy Path 测试

tags: [crosschain, layerzero, messaging, foundry, solidity, testing, bridge, happy-path]

## 背景 / 目标

今天的目标是把“一次正常跨链”在 Foundry 测试里完整跑通：

- **Src 链（A）**：用户发起跨链 → **burn**（或 lock）→ 通过 endpoint 发消息  
- **Dst 链（B）**：endpoint 回调 `lzReceive` → **mint**（或 release）→ 用户在 B 链收到资产

> 本文默认用 **Burn/Mint**（最省事、最适合先跑通），末尾给出 **Lock/Release** 的替换点。

---

## 一、核心原理（通俗版）

一次跨链消息可以理解为一个“包裹”：

- `srcChainId`：来自哪条链
- `srcApp`：源链谁发的（通常是源链 Bridge 合约地址）
- `nonce`：消息序号（endpoint 生成/维护）
- `payload`：业务数据（例如 `to`、`amount`）

Dst 链收到消息后，会由 endpoint 调用接收合约的回调：

```solidity
lzReceive(srcChainId, srcApp, nonce, payload, messageId)
```

在 `lzReceive` 里你需要做两件事：

1) **验证调用合法**：必须是可信 endpoint 来调用，且 `srcApp` 必须在白名单  
2) **执行业务逻辑**：解码 payload，执行 mint / release

---

## 二、资产跨链的两种常见模型

### 方案 A：Burn / Mint（本文采用 ✅）

- Src 链：用户资产在 A 链 **burn**
- Dst 链：消息到达 B 链后 **mint** 给用户

优点：实现简单，适合学习消息链路、测试结构  
缺点：Dst 链 token 必须允许桥合约 mint（或 token 逻辑足够简化）

### 方案 B：Lock / Release（替换点在文末）

- Src 链：把资产锁到桥合约/vault（`transferFrom` 到 vault）
- Dst 链：从 vault 释放给用户（`transfer` 给用户）

优点：更贴近“库存式跨链/流动性池式跨链”  
缺点：需要预先准备 vault 库存，逻辑多一点

---

## 三、知识点清单

### 1) 跨链消息结构与可信校验
- endpoint 负责：生成 `nonce`、把消息投递到 dst endpoint、由 dst endpoint 回调 `lzReceive`
- 接收端必须限制：
  - `msg.sender == endpoint`（只允许 endpoint 回调）
  - `trustedSrcApp[srcChainId] == srcApp`（只允许指定源桥）

### 2) payload 编解码（你经常会见到）
```solidity
bytes memory payload = abi.encode(to, amount);
(address to, uint256 amount) = abi.decode(payload, (address, uint256));
```

这里 `(address, uint256)` 是“告诉编译器 payload 的结构类型”，这样才能正确解码。

### 3) Foundry 测试技巧
- `vm.prank(addr)`：模拟不同调用者（用户/endpoint）
- 断言状态：`assertEq(token.balanceOf(user), ...)`

---

## 四、实现步骤（Burn/Mint Happy Path）

### Step 0：准备组件
你至少需要 4 个合约：

1) `MockEndpoint`：模拟跨链 endpoint（A/B 各一个）
2) `TokenA`：Src 链 token（支持 burn）
3) `TokenB`：Dst 链 token（支持 mint）
4) `BridgeA / BridgeB`：桥合约（A 发消息、B 收消息并 mint）

### Step 1：在 setUp 部署双链环境
- 部署 `endpointA(chainId=A)` 与 `endpointB(chainId=B)`
- 配置互相为 remote（A → B，B → A）
- 部署 `tokenA`、`tokenB`
- 部署 `bridgeA(tokenA, endpointA)`、`bridgeB(tokenB, endpointB)`
- 在 `bridgeB` 设置可信源：`trustedSrcApp[A] = bridgeA`

### Step 2：为用户初始化 src 链余额
- `tokenA.mint(user, 100 ether)`

### Step 3：用户在 A 链发起跨链
- `bridgeA.bridgeTo(chainB, bridgeB, user, amount)`
- A 链动作：`burn(user, amount)` + `endpoint.send(...)`

### Step 4：B 链收到消息并 mint
- mock endpoint 投递时会调用：`bridgeB.lzReceive(...)`
- B 链动作：解码 `payload`，执行 `tokenB.mint(user, amount)`

### Step 5：测试断言
- A 链余额减少（burn 生效）
- B 链余额增加（mint 生效）

---

## 五、参考代码（最小可跑通骨架）

> 说明：下面是“最小化示例”，你可以直接复制到仓库里：
>
> - `src/bridge/SimpleMintBurnERC20.sol`
> - `src/bridge/MockEndpoint.sol`
> - `src/bridge/BurnMintBridge.sol`
> - `test/bridge/D30_NormalCrossChain_BurnMint.t.sol`

### 1) SimpleMintBurnERC20.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SimpleMintBurnERC20 {
    string public name = "BridgeToken";
    string public symbol = "BT";
    uint8  public decimals = 18;

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 amount);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(balanceOf[from] >= amount, "INSUFFICIENT");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}
```

### 2) MockEndpoint.sol（最小跨链投递）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILZReceiverLike {
    function lzReceive(
        uint16 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload,
        bytes32 messageId
    ) external;
}

contract MockEndpoint {
    uint16 public immutable chainId;
    uint64 public nonce;

    mapping(uint16 => MockEndpoint) public remotes;

    constructor(uint16 _chainId) {
        chainId = _chainId;
    }

    function setRemote(uint16 dstChainId, MockEndpoint dstEndpoint) external {
        remotes[dstChainId] = dstEndpoint;
    }

    function send(uint16 dstChainId, address dstApp, bytes calldata payload) external {
        nonce++;

        MockEndpoint dstEndpoint = remotes[dstChainId];
        require(address(dstEndpoint) != address(0), "NO_REMOTE");

        bytes32 messageId = keccak256(abi.encode(chainId, msg.sender, nonce, payload));
        dstEndpoint.deliver(chainId, msg.sender, dstApp, nonce, payload, messageId);
    }

    function deliver(
        uint16 srcChainId,
        address srcApp,
        address dstApp,
        uint64 _nonce,
        bytes calldata payload,
        bytes32 messageId
    ) external {
        ILZReceiverLike(dstApp).lzReceive(srcChainId, srcApp, _nonce, payload, messageId);
    }
}
```

### 3) BurnMintBridge.sol（A 侧 burn+send，B 侧 lzReceive+mint）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SimpleMintBurnERC20.sol";

interface IEndpoint {
    function send(uint16 dstChainId, address dstApp, bytes calldata payload) external;
}

interface ILZReceiverLike {
    function lzReceive(
        uint16 srcChainId,
        address srcApp,
        uint64 nonce,
        bytes calldata payload,
        bytes32 messageId
    ) external;
}

contract BurnMintBridge is ILZReceiverLike {
    SimpleMintBurnERC20 public immutable token;
    IEndpoint public immutable endpoint;

    mapping(uint16 => address) public trustedSrcApp; // srcChainId => srcBridge

    error NotEndpoint();
    error UntrustedSource(uint16 srcChainId, address srcApp);

    constructor(SimpleMintBurnERC20 _token, IEndpoint _endpoint) {
        token = _token;
        endpoint = _endpoint;
    }

    function setTrustedSrcApp(uint16 srcChainId, address srcBridge) external {
        trustedSrcApp[srcChainId] = srcBridge;
    }

    function bridgeTo(uint16 dstChainId, address dstBridge, address to, uint256 amount) external {
        token.burn(msg.sender, amount);

        bytes memory payload = abi.encode(to, amount);
        endpoint.send(dstChainId, dstBridge, payload);
    }

    function lzReceive(
        uint16 srcChainId,
        address srcApp,
        uint64 /*nonce*/,
        bytes calldata payload,
        bytes32 /*messageId*/
    ) external override {
        if (msg.sender != address(endpoint)) revert NotEndpoint();
        if (trustedSrcApp[srcChainId] != srcApp) revert UntrustedSource(srcChainId, srcApp);

        (address to, uint256 amount) = abi.decode(payload, (address, uint256));
        token.mint(to, amount);
    }
}
```

### 4) D30_NormalCrossChain_BurnMint.t.sol（Happy Path 测试）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/bridge/SimpleMintBurnERC20.sol";
import "../../src/bridge/MockEndpoint.sol";
import "../../src/bridge/BurnMintBridge.sol";

contract D30_NormalCrossChain_BurnMint_Test is Test {
    uint16 constant CHAIN_A = 1;
    uint16 constant CHAIN_B = 2;

    MockEndpoint endpointA;
    MockEndpoint endpointB;

    SimpleMintBurnERC20 tokenA;
    SimpleMintBurnERC20 tokenB;

    BurnMintBridge bridgeA;
    BurnMintBridge bridgeB;

    address user = address(0xA11CE);

    function setUp() public {
        endpointA = new MockEndpoint(CHAIN_A);
        endpointB = new MockEndpoint(CHAIN_B);

        endpointA.setRemote(CHAIN_B, endpointB);
        endpointB.setRemote(CHAIN_A, endpointA);

        tokenA = new SimpleMintBurnERC20();
        tokenB = new SimpleMintBurnERC20();

        bridgeA = new BurnMintBridge(tokenA, IEndpoint(address(endpointA)));
        bridgeB = new BurnMintBridge(tokenB, IEndpoint(address(endpointB)));

        bridgeB.setTrustedSrcApp(CHAIN_A, address(bridgeA));

        tokenA.mint(user, 100 ether);
    }

    function test_normalCrossChain_burnOnA_mintOnB() public {
        uint256 amount = 10 ether;

        uint256 aBefore = tokenA.balanceOf(user);
        uint256 bBefore = tokenB.balanceOf(user);

        vm.prank(user);
        bridgeA.bridgeTo(CHAIN_B, address(bridgeB), user, amount);

        assertEq(tokenA.balanceOf(user), aBefore - amount);
        assertEq(tokenB.balanceOf(user), bBefore + amount);
    }
}
```

---

## 六、审计视角 Checklist（Happy Path 也要写）

即使今天只做正常路径，审计时会立刻看这些“边界与信任”点：

### A. 入口与信任边界
- [ ] `lzReceive` 是否 **只允许 endpoint 调用**（`msg.sender == endpoint`）
- [ ] 是否校验 `srcApp` 白名单（`trustedSrcApp[srcChainId] == srcApp`）
- [ ] 是否考虑 dstBridge 地址可能被替换/钓鱼（生产环境一般会有更严格 remote 配置）

### B. payload 安全与解码
- [ ] `abi.decode` 的类型签名必须与 `abi.encode` 一致
- [ ] payload 是否包含必要字段（`to`、`amount` 之外可能还要 `dstChainId`、`token`、`fee` 等）

### C. 资金与会计一致性
- [ ] Burn/Mint：是否保证 **src burn 成功才发送消息**（否则会“无 burn 却 mint”）
- [ ] Lock/Release：vault 是否有足够库存、是否会因余额不足导致 stuck
- [ ] 金额边界：`amount == 0` 是否允许？（建议显式拒绝或定义行为）

### D. 可升级/配置风险（以后会扩展）
- [ ] `setTrustedSrcApp` 是否需要权限控制（onlyOwner / roles）
- [ ] endpoint 地址是否可更改？更改是否会破坏信任边界

> 下一天/后续任务会在此 Happy Path 基础上加入：重放保护（messageId 去重）、nonce/顺序、失败重试、费用、攻击用例等。

---

## 七、Lock/Release 替换点（如果你改选这个）

把 `bridgeTo()` 里的：
- `token.burn(msg.sender, amount);`

替换成：
- `token.transferFrom(msg.sender, address(this), amount);`  // lock

把 `lzReceive()` 里的：
- `token.mint(to, amount);`

替换成：
- `token.transfer(to, amount);`  // release

并在测试 setUp 中给 `bridgeB` 预存库存（示例）：
- `tokenB.mint(address(bridgeB), 1_000_000 ether);`

---

## 八、运行命令

```bash
cd labs/foundry-labs
forge test --match-contract D30_NormalCrossChain_BurnMint_Test -vvv
```

---

## 九、今日产出清单（建议写到 PR / Commit 里）
- ✅ D30 Happy Path 跨链测试跑通（Burn/Mint）
- ✅ `lzReceive` 信任校验（endpoint + trusted srcApp）
- ✅ payload 编解码模板可复用
- ✅ 审计视角 checklist 落地
