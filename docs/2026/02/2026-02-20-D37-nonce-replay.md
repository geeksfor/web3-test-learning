# 2026-02-20 - D37｜Nonce 重放：不带 nonce 的错误实现 → 同签名可重复；攻击测试 + 修复回归

tags: [foundry, forge, solidity, security, replay, signature, ecdsa, nonce]

## 背景 / 目标

很多“凭签名领取/铸币/放行”的合约都会做类似逻辑：

- 用户提交：`to / amount / signature`
- 合约验签通过 → 执行发放

**如果签名内容里没有 nonce（一次性编号），并且合约也没有记录“这张票据是否已经用过”**，那么同一份签名可以被无限次重复提交 —— 这就是 **重放（Replay）** 漏洞。

今天目标：

1) 写一个 **漏洞版本**：签名只覆盖 `(to, amount)`，**不带 nonce**，也不做已用记录  
2) 写 **攻击测试**：同一份签名 `claim()` 两次 → 余额翻倍（漏洞复现）  
3) 写 **修复版本**：把 `nonce` 纳入签名，且 **记录 nonce 已用**  
4) 写 **回归测试**：第二次重放必须 revert，且状态不变

---

## 知识点与原理（通俗易懂）

### 1) 什么是“重放（Replay）”？

把签名理解为“可兑现票据”：

- 合约只要验证票据是真的，就给你发奖励
- 如果票据**没有唯一编号**，也没有**核销记录**
- 那么你复印这张票据，拿同一张票据重复兑换都能成功

**结果：同一份签名可重复使用，资产被重复发放。**

### 2) nonce 的作用是什么？

nonce = “一次性编号 / 序号”，用于让每张票据“只可用一次”。

典型修复策略：

- 把 `nonce` 纳入签名内容：`sign(to, amount, nonce, ...)`
- 合约在成功执行后记录：`usedNonce[to][nonce] = true`
- 再次使用同 nonce 时，直接拒绝

### 3) 常见错误实现（导致重放）

- ✅ **没有把 nonce/deadline 纳入签名内容**
- ✅ **没有任何“已使用”记录**
- ✅ 更进阶：缺域隔离（`chainId`、`address(this)`、`srcApp/dstApp` 等），导致跨链/跨合约重放

---

## 实现步骤（建议按此顺序提交）

### Step 1：实现漏洞合约（不带 nonce）

文件：`src/vulns/D37_NonceReplayVuln.sol`

核心错误：

- `hash = keccak256( to, amount )`
- `digest = toEthSignedMessageHash(hash)`
- recover 出签名者正确就发放
- **没有 nonce，也不存 used**

### Step 2：写攻击测试（同签名重放两次）

文件：`test/vulns/D37_NonceReplay.t.sol`

断言：

- 第一次 `claim()` → `balanceOf[alice] == amount`
- 第二次重放同签名 → `balanceOf[alice] == 2*amount`

### Step 3：实现修复合约（加入 nonce + 记录已用）

文件：`src/vulns/D37_NonceReplayFixed.sol`

修复要点：

- `hash = keccak256( to, amount, nonce )`
- 执行前检查：`if (usedNonce[to][nonce]) revert NonceUsed(to, nonce);`
- 验签通过后：**先标记 nonce 已用，再发放**（CEI 思路）

### Step 4：写修复回归测试（第二次必须 revert + 状态不变）

关键点：Foundry 断言 custom error 最稳的写法是匹配 **selector + 参数**：

```solidity
vm.expectRevert(abi.encodeWithSelector(
    D37_NonceReplayFixed.NonceUsed.selector,
    alice,
    nonce
));
```

---

## 参考代码（可直接使用）

> 说明：下面用 OpenZeppelin 的 ECDSA + MessageHashUtils（适配 OZ v5）。  
> 如果你是 OZ v4，也可以改成 `ECDSA.toEthSignedMessageHash(hash)` 的静态调用写法。

### 1) 漏洞版本合约：D37_NonceReplayVuln

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract D37_NonceReplayVuln {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    error InvalidSignature();

    address public immutable signer;
    mapping(address => uint256) public balanceOf;

    constructor(address _signer) {
        signer = _signer;
    }

    function _hash(address to, uint256 amount) internal pure returns (bytes32) {
        // ❌ 漏洞：没有 nonce
        return keccak256(abi.encodePacked(to, amount));
    }

    function claim(address to, uint256 amount, bytes calldata sig) external {
        bytes32 digest = _hash(to, amount).toEthSignedMessageHash();
        address recovered = ECDSA.recover(digest, sig);
        if (recovered != signer) revert InvalidSignature();

        balanceOf[to] += amount;
    }
}
```

### 2) 修复版本合约：D37_NonceReplayFixed

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract D37_NonceReplayFixed {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    error InvalidSignature();
    error NonceUsed(address to, uint256 nonce);

    address public immutable signer;
    mapping(address => uint256) public balanceOf;

    mapping(address => mapping(uint256 => bool)) public usedNonce;

    constructor(address _signer) {
        signer = _signer;
    }

    function _hash(address to, uint256 amount, uint256 nonce) internal pure returns (bytes32) {
        // ✅ 修复：加入 nonce（可再加入 chainid/address(this) 做域隔离）
        return keccak256(abi.encodePacked(to, amount, nonce));
    }

    function claim(address to, uint256 amount, uint256 nonce, bytes calldata sig) external {
        if (usedNonce[to][nonce]) revert NonceUsed(to, nonce);

        bytes32 digest = _hash(to, amount, nonce).toEthSignedMessageHash();
        address recovered = ECDSA.recover(digest, sig);
        if (recovered != signer) revert InvalidSignature();

        // ✅ 先标记，再发放（CEI 思路）
        usedNonce[to][nonce] = true;
        balanceOf[to] += amount;
    }
}
```

### 3) Foundry 测试：漏洞复现 + 修复回归

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D37_NonceReplayVuln.sol";
import "../../src/vulns/D37_NonceReplayFixed.sol";

contract D37_NonceReplay_Test is Test {
    uint256 signerPk;
    address signer;

    address alice;

    function setUp() public {
        signerPk = 0xA11CE;
        signer = vm.addr(signerPk);
        alice = makeAddr("alice");
    }

    function _signVuln(address to, uint256 amount) internal view returns (bytes memory sig) {
        bytes32 msgHash = keccak256(abi.encodePacked(to, amount));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _signFixed(address to, uint256 amount, uint256 nonce) internal view returns (bytes memory sig) {
        bytes32 msgHash = keccak256(abi.encodePacked(to, amount, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function test_vuln_sameSignature_canBeReplayed() public {
        D37_NonceReplayVuln vuln = new D37_NonceReplayVuln(signer);

        uint256 amount = 100;
        bytes memory sig = _signVuln(alice, amount);

        vuln.claim(alice, amount, sig);
        assertEq(vuln.balanceOf(alice), 100);

        // ✅ 重放同一个签名
        vuln.claim(alice, amount, sig);
        assertEq(vuln.balanceOf(alice), 200);
    }

    function test_fixed_sameSignature_replay_reverts() public {
        D37_NonceReplayFixed fixedC = new D37_NonceReplayFixed(signer);

        uint256 amount = 100;
        uint256 nonce = 7;
        bytes memory sig = _signFixed(alice, amount, nonce);

        fixedC.claim(alice, amount, nonce, sig);
        assertEq(fixedC.balanceOf(alice), 100);

        // ✅ Foundry 最稳的 custom error 匹配方式：selector + 参数
        vm.expectRevert(abi.encodeWithSelector(
            D37_NonceReplayFixed.NonceUsed.selector,
            alice,
            nonce
        ));
        fixedC.claim(alice, amount, nonce, sig);

        // 状态不变
        assertEq(fixedC.balanceOf(alice), 100);
        assertTrue(fixedC.usedNonce(alice, nonce));
    }
}
```

---

## 运行方式

```bash
cd labs/foundry-labs
forge test --match-contract D37_NonceReplay_Test -vvv
```

预期：

- `test_vuln_sameSignature_canBeReplayed`：PASS（漏洞被复现，余额翻倍）
- `test_fixed_sameSignature_replay_reverts`：PASS（修复有效，重放被拒绝）

---

## 审计视角 Checklist（今天的“检查清单”）

> 看到“签名授权/签名领取/跨链消息/离线批准”等逻辑时，优先按这份清单排雷。

### A. 防重放（Replay Protection）

- [ ] 签名内容是否包含 **nonce**（一次性编号 / 序号）？
- [ ] 合约是否记录 **nonce 已使用**（`usedNonce` / `processed` / `bitmap`）？
- [ ] 成功执行后是否先更新状态，再外部交互（CEI）？

### B. 域隔离（Domain Separation）

- [ ] digest 是否包含 `address(this)`（防同签名在不同合约重放）？
- [ ] digest 是否包含 `block.chainid`（防跨链重放）？
- [ ] 若是跨链消息：是否包含 `srcChainId/srcApp/dstChainId/dstApp` 等域信息？

### C. 过期控制（可选但常见）

- [ ] 是否需要 `deadline/expiry`（防“老签名永久有效”）？
- [ ] 是否对 nonce/时间窗口做合理边界约束？

### D. 签名实现细节

- [ ] ECDSA recover 是否使用明确的 digest 标准（EIP-191 或 EIP-712）？
- [ ] 是否避免 `abi.encodePacked` 的可碰撞风险（多动态类型时建议 `abi.encode`）？
- [ ] 是否对 signer 轮换/多签策略有设计（运营签名者更换）？

---

## 今日小结

- **漏洞本质**：签名缺少“唯一性”，导致同一签名可重复执行  
- **修复核心**：nonce 入签 + nonce 已用记录（必要时再加 domain separation / deadline）  
- **测试思路**：同签名重复调用 → 漏洞版成功翻倍；修复版第二次必须 revert 且状态不变
