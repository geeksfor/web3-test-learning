# 2026-02-21 — D38 域隔离：deadline / chainId / contract address（换链/换合约重放示例）

tags: [foundry, forge, solidity, signature, replay, domain-separation, chainid, deadline, audit]

## 背景 / 目标（通俗版）
你让用户“签个名”本质是在签一段**意图**，例如：

> “我同意在某个合约上，让某个人执行一次操作（参数固定），并且只能在某个期限前有效。”

如果签名里**没把“在哪条链、哪个合约实例”说清楚**，攻击者就能把同一份签名拿去**别的链**或**别的合约地址**继续用 —— 这就是 **域隔离（domain separation）**要解决的问题。

本日目标：
1. 写一个**错误示例（vuln）**：签名不绑定 `chainId` 和 `address(this)`，证明“换链/换合约仍能用”
2. 写一个**修复版本（fixed）**：把 `block.chainid` + `address(this)` 加入签名 digest（域隔离）
3. 写 Foundry 测试：覆盖漏洞证明 + 修复回归
4. 把今天的提问内容（换链为什么地址不变、`_verify` 逐行解释）写进文档，便于复习

---

## 知识点（通俗易懂）

### 1) deadline：解决“过期签名还被用”
- 没有 `deadline`：签名可能几年后仍有效（只要 nonce 没挡住或实现有坑）
- 有 `deadline`：`block.timestamp > deadline` 直接拒绝，签名“限时”

### 2) chainId：解决“换链重放”
同一个私钥在不同链上的 EOA 地址**通常相同**（见下方提问解释），如果签名 digest **不包含 chainId**，那么同一签名可能在链 A、链 B 都能通过验签。

### 3) contract address（verifyingContract / address(this)）：解决“换合约重放”
如果你部署了两份逻辑一致的合约 A/B，地址不同：
- digest 不包含 `address(this)` → 同一签名可能在 A、B 都有效

> 一句话记忆：  
> **deadline = 限时**；**chainId = 限链**；**address(this) = 限合约实例**。三者合起来就是“域隔离”。

---

## 实现步骤（按任务拆解）

### Step 0：建议分支名
- `d38-domain-separation-deadline-chainid-contract`

### Step 1：实现漏洞合约（Bad）
digest 只包含业务参数 + nonce + deadline，不包含 chainId / address(this)  
✅ 预期：同签名在另一合约实例、或 chainId 改变后仍可能通过（漏洞成立）

### Step 2：实现修复合约（Good）
digest 加入 `block.chainid` + `address(this)`  
✅ 预期：换链/换合约后必须 `BadSig`（修复成立）

### Step 3：写测试（必须覆盖）
- Bad：同签名在合约 A 成功
- Bad：同签名在合约 B（不同地址）也成功（证明“换合约重放”）
- Bad：切换 `vm.chainId()` 后仍能用（证明“换链重放”）
- Good：换合约 / 换链必须失败（回归）
- Good：过期 deadline 必须失败

---

## 参考代码（最小可跑版）

> 建议文件路径（与你之前 D30~D37 风格一致）：
- `src/vulns/D38_DomainSeparationBad.sol`
- `src/fixed/D38_DomainSeparationGood.sol`
- `test/vulns/D38_DomainSeparation.t.sol`

### A) 漏洞合约：未做域隔离（Bad）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract D38_DomainSeparationBad {
    error Expired(uint256 nowTs, uint256 deadline);
    error NonceUsed(address owner, uint256 nonce);
    error BadSig();

    mapping(address => mapping(uint256 => bool)) public usedNonce;
    uint256 public counter;

    function doAction(
        address owner,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata sig
    ) external {
        if (block.timestamp > deadline) revert Expired(block.timestamp, deadline);
        if (usedNonce[owner][nonce]) revert NonceUsed(owner, nonce);

        bytes32 digest = _digestBad(owner, msg.sender, amount, nonce, deadline);
        if (!_verify(owner, digest, sig)) revert BadSig();

        usedNonce[owner][nonce] = true;
        counter += amount;
    }

    // ❌ 漏洞：digest 里没有 chainId、没有 address(this)
    function _digestBad(
        address owner,
        address spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (bytes32) {
        bytes32 h = keccak256(abi.encode(owner, spender, amount, nonce, deadline));
        // EIP-191 personal_sign 风格
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }

    function _verify(address signer, bytes32 digest, bytes calldata sig) internal pure returns (bool) {
        if (sig.length != 65) return false;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        // 兼容 27/28 与 0/1
        if (v < 27) v += 27;
        address recovered = ecrecover(digest, v, r, s);
        return recovered == signer && recovered != address(0);
    }
}
```

### B) 修复合约：加入 chainId + contract address（Good）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract D38_DomainSeparationGood {
    error Expired(uint256 nowTs, uint256 deadline);
    error NonceUsed(address owner, uint256 nonce);
    error BadSig();

    mapping(address => mapping(uint256 => bool)) public usedNonce;
    uint256 public counter;

    function doAction(
        address owner,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata sig
    ) external {
        if (block.timestamp > deadline) revert Expired(block.timestamp, deadline);
        if (usedNonce[owner][nonce]) revert NonceUsed(owner, nonce);

        bytes32 digest = _digestGood(owner, msg.sender, amount, nonce, deadline);
        if (!_verify(owner, digest, sig)) revert BadSig();

        usedNonce[owner][nonce] = true;
        counter += amount;
    }

    // ✅ 修复：digest 加入 block.chainid + address(this)，实现域隔离
    function _digestGood(
        address owner,
        address spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 h = keccak256(
            abi.encode(owner, spender, amount, nonce, deadline, block.chainid, address(this))
        );
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }

    function _verify(address signer, bytes32 digest, bytes calldata sig) internal pure returns (bool) {
        if (sig.length != 65) return false;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v < 27) v += 27;
        address recovered = ecrecover(digest, v, r, s);
        return recovered == signer && recovered != address(0);
    }
}
```

### C) 测试：证明 Bad 可“换合约/换链重放”，Good 不行

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {D38_DomainSeparationBad} from "../src/vulns/D38_DomainSeparationBad.sol";
import {D38_DomainSeparationGood} from "../src/fixed/D38_DomainSeparationGood.sol";

contract D38_DomainSeparation_Test is Test {
    uint256 ownerPk;
    address owner;
    address spender;

    function setUp() public {
        ownerPk = 0xA11CE;
        owner = vm.addr(ownerPk);
        spender = makeAddr("spender");
    }

    // ---- helper: 生成 Bad 的签名（不绑定 chainId/contract）
    function signBad(
        address _owner,
        address _spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal returns (bytes memory sig) {
        bytes32 h = keccak256(abi.encode(_owner, _spender, amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    // ---- helper: 生成 Good 的签名（绑定 chainId + verifyingContract）
    function signGood(
        address verifyingContract,
        uint256 chainId,
        address _owner,
        address _spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal returns (bytes memory sig) {
        bytes32 h = keccak256(
            abi.encode(_owner, _spender, amount, nonce, deadline, chainId, verifyingContract)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    // ---------------- BAD：漏洞证明 ----------------

    function test_bad_replay_on_other_contract_succeeds() public {
        D38_DomainSeparationBad a = new D38_DomainSeparationBad();
        D38_DomainSeparationBad b = new D38_DomainSeparationBad(); // 不同地址

        uint256 amount = 7;
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 days;

        // 在 A 生成签名（但签名并不绑定合约地址）
        bytes memory sig = signBad(owner, spender, amount, nonce, deadline);

        vm.prank(spender);
        a.doAction(owner, amount, nonce, deadline, sig);
        assertEq(a.counter(), amount);

        // ❌ 漏洞：同 sig 拿到 B 仍能用（digest 不含 address(this)）
        vm.prank(spender);
        b.doAction(owner, amount, nonce, deadline, sig);
        assertEq(b.counter(), amount);
    }

    function test_bad_replay_after_chain_change_succeeds() public {
        D38_DomainSeparationBad c = new D38_DomainSeparationBad();

        uint256 amount = 5;
        uint256 deadline = block.timestamp + 1 days;

        // 第一次（chainId 先保持默认）
        bytes memory sig1 = signBad(owner, spender, amount, 1, deadline);
        vm.prank(spender);
        c.doAction(owner, amount, 1, deadline, sig1);
        assertEq(c.counter(), amount);

        // 模拟“换链/分叉环境”
        vm.chainId(999);

        // ❌ 漏洞：chainId 变了，仍能按同样规则生成可用签名（digest 规则与 chainId 无关）
        bytes memory sig2 = signBad(owner, spender, amount, 2, deadline);
        vm.prank(spender);
        c.doAction(owner, amount, 2, deadline, sig2);
        assertEq(c.counter(), amount + amount);
    }

    // ---------------- GOOD：修复验证 ----------------

    function test_good_replay_on_other_contract_reverts() public {
        D38_DomainSeparationGood a = new D38_DomainSeparationGood();
        D38_DomainSeparationGood b = new D38_DomainSeparationGood();

        uint256 amount = 7;
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 days;

        uint256 cid = block.chainid;

        // 绑定合约 A 地址 + chainId 的签名
        bytes memory sigA = signGood(address(a), cid, owner, spender, amount, nonce, deadline);

        vm.prank(spender);
        a.doAction(owner, amount, nonce, deadline, sigA);
        assertEq(a.counter(), amount);

        // ✅ 修复：同签名拿到合约 B 必须失败（BadSig）
        vm.prank(spender);
        vm.expectRevert(D38_DomainSeparationGood.BadSig.selector);
        b.doAction(owner, amount, nonce, deadline, sigA);
    }

    function test_good_replay_after_chain_change_reverts() public {
        D38_DomainSeparationGood c = new D38_DomainSeparationGood();

        uint256 amount = 9;
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 days;

        uint256 cid = block.chainid;
        bytes memory sig = signGood(address(c), cid, owner, spender, amount, nonce, deadline);

        vm.prank(spender);
        c.doAction(owner, amount, nonce, deadline, sig);
        assertEq(c.counter(), amount);

        vm.chainId(777);

        // ✅ 修复：chainId 变了，旧签名必须失效（BadSig）
        vm.prank(spender);
        vm.expectRevert(D38_DomainSeparationGood.BadSig.selector);
        c.doAction(owner, amount, 2, deadline, sig);
    }

    function test_good_deadline_expired_reverts() public {
        D38_DomainSeparationGood c = new D38_DomainSeparationGood();

        uint256 amount = 1;
        uint256 nonce = 1;
        uint256 deadline = block.timestamp - 1; // 已过期

        bytes memory sig = signGood(address(c), block.chainid, owner, spender, amount, nonce, deadline);

        vm.prank(spender);
        vm.expectRevert(D38_DomainSeparationGood.Expired.selector);
        c.doAction(owner, amount, nonce, deadline, sig);
    }
}
```

运行：
```bash
forge test --match-contract D38_DomainSeparation_Test -vvv
```

---

## 提问内容沉淀（写进文档，便于复习）

### Q1：为什么同一个私钥在不同链上地址还是一样？
**因为 EOA 地址的生成过程不包含 chainId。**

EOA 地址（外部账户）来自：
- 私钥 → 公钥（椭圆曲线）
- 公钥 → keccak256 → 取后 20 字节 → address

这套数学过程里没有“链/网络/chainId”。  
所以同一个私钥，在主网、测试网、L2 上推导出的地址都一样。

直觉类比：
- 地址像“身份证号”（由私钥决定）
- 链像“国家/系统”（你拿同一身份证号去不同系统使用）

因此，如果你的**消息签名 digest 不包含 chainId**，就可能发生“换链重放”。

### Q2：逐行解释 `_verify`（验签函数）
目标：从 `digest + sig(r,s,v)` 反推出签名者地址，看是不是等于 `signer`。

```solidity
function _verify(address signer, bytes32 digest, bytes calldata sig) internal pure returns (bool) {
    if (sig.length != 65) return false;
```
- ECDSA 标准签名是 65 字节：`r(32) + s(32) + v(1)`，不对就直接失败。

```solidity
    bytes32 r;
    bytes32 s;
    uint8 v;
```
- 准备三个变量来装签名拆出来的三段。

```solidity
    assembly {
        r := calldataload(sig.offset)
        s := calldataload(add(sig.offset, 32))
        v := byte(0, calldataload(add(sig.offset, 64)))
    }
```
- `sig` 在 calldata 里是连续字节数组：
  - 偏移 0..31 是 r
  - 偏移 32..63 是 s
  - 偏移 64 是 v（1 字节）
- `calldataload` 每次读 32 字节，所以读 v 时先读 32 字节，再用 `byte(0, ...)` 取第一个字节。

```solidity
    if (v < 27) v += 27;
```
- 有些库给 v 是 `0/1`，但 `ecrecover` 常用 `27/28`，这里做兼容转换。

```solidity
    address recovered = ecrecover(digest, v, r, s);
    return recovered == signer && recovered != address(0);
}
```
- `ecrecover`：把签名还原成签名者地址
- 既要匹配 `signer`，也要避免无效签名返回 `address(0)` 误判。

---

## 审计视角（Checklist）
签名授权/MetaTx/Permit/跨链消息里，经常要检查：

1. **域隔离是否完整**
   - [ ] digest 是否包含 `address(this)`（verifyingContract）
   - [ ] digest 是否包含 `block.chainid`
2. **时效性**
   - [ ] 是否有 `deadline` 且校验正确（`block.timestamp > deadline`）
3. **一次性**
   - [ ] nonce 是否一次性使用（mapping 标记，校验后置位）
4. **编码安全**
   - [ ] 用 `abi.encode`（避免 `abi.encodePacked` 拼接歧义）
5. **验签边界**
   - [ ] v 兼容（0/1 vs 27/28）
   - [ ] `recovered != address(0)`
   - [ ]（进阶）low-s 规范化 / 用 OZ `ECDSA.recover` 降低坑位
6. **重放面**
   - [ ] 同签名能否在不同合约实例复用？
   - [ ] 同签名能否在不同链/分叉环境复用？

---

## 今日 Commit 建议
```text
feat(d38): add domain separation (deadline/chainId/verifyingContract) vuln+fix with regression tests and notes
```
