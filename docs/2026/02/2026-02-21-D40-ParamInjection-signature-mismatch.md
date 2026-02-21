# D40｜参数注入：签名内容与执行内容不一致（to/amount 未纳入签名）

> 关键词：parameter injection / intent mismatch / meta-tx / signature replay / nonce / deadline / domain separation  
> 目标：复现“签名没覆盖关键参数 → 攻击者可替换执行参数（to/amount）”并写攻击测试；给出修复与回归测试。

---

## 1. 一句话理解

**用户线下签名表达的“授权意图（intent）”不完整**（比如签名里没写清 `to`/`amount`），  
攻击者拿到这份签名后，在链上调用时就能**注入（替换）这些未被签名约束的参数**，从而把钱转给自己、把金额改大。

---

## 2. 背景：为什么“签名授权”容易出问题？

很多协议会提供 **meta-transaction / 签名授权执行** 的接口，例如：

- `transferWithSig(from, to, amount, deadline, sig)`（免授权/免交易的转账）
- `withdrawWithSig(owner, to, shares, ...)`
- `claimWithSig(user, receiver, amount, ...)`
- 以及 `permit`/`permit2`/EIP-712 变体

这类接口共同点是：

1) 用户在链下签名  
2) 任意执行者（relayer/attacker）把签名带上链调用  
3) 合约 `ecrecover` 验证签名属于用户，然后执行

**核心安全要求：签名承诺的内容 = 链上真正执行的内容**。  
只要两者不一致，就会出现“参数注入 / 意图错配”。

---

## 3. 漏洞原理（通俗版）

### 3.1 漏洞版（错误做法）
合约验签的 `digest` 只包含：

- `from`
- `nonce`
- `deadline`

却 **没有包含**：

- `to`
- `amount`

这意味着：只要签名能证明“from 同意执行一次”，至于给谁、给多少，**验签根本不关心**。  
攻击者就能调用：

- `to = attacker`
- `amount = 更大`

也照样通过验签。

### 3.2 修复版（正确做法）
把执行关键参数全部纳入签名，并做域隔离：

- `from, to, amount, nonce, deadline`
- **domain separation**：`chainId` + `verifyingContract(address(this))`

这样攻击者即使拿到了签名，也**无法修改 to/amount**，否则 digest 不一致 → `BadSig`。

---

## 4. 攻击流程（你写测试时就是按这个演）

以 Alice 为签名者：

1) Alice 线下签一份“授权”（漏洞版：签名里不含 `to/amount`）  
2) attacker 拿到签名（或作为 relayer）  
3) attacker 调用 `transferWithSig(alice, attacker, 900, deadline, sig)`  
4) 合约验签通过（因为 digest 没关心 to/amount）  
5) 余额被盗走：`alice -> attacker`

---

## 5. 代码实现（最小可复现）

> 说明：以下是最小化教学实现（用 `toEthSignedMessageHash` 做演示）。  
> 真实项目更推荐 EIP-712 typed data（见“审计视角建议”）。

### 5.1 漏洞合约：签名未包含 to/amount

文件建议：`labs/foundry-labs/src/vulns/D40_ParamInjectionVuln.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract D40_ParamInjectionVuln {
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public nonces;

    error BadSig();
    error Expired();

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    // ❌ 漏洞：digest 没有绑定 to/amount
    function transferWithSig(
        address from,
        address to,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > deadline) revert Expired();

        uint256 nonce = nonces[from];

        bytes32 digest = keccak256(
            abi.encodePacked("D40_TRANSFER_V1", from, nonce, deadline)
        );

        address recovered = ecrecover(toEthSignedMessageHash(digest), v, r, s);
        if (recovered != from) revert BadSig();

        nonces[from] = nonce + 1;

        // ✅ 但执行参数 to/amount 是外部输入，可被注入
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function toEthSignedMessageHash(bytes32 h) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }
}
```

---

### 5.2 修复合约：签名覆盖执行参数 + 域隔离

文件建议：`labs/foundry-labs/src/fixed/D40_ParamInjectionFixed.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract D40_ParamInjectionFixed {
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public nonces;

    error BadSig();
    error Expired();

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transferWithSig(
        address from,
        address to,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > deadline) revert Expired();

        uint256 nonce = nonces[from];

        // ✅ 修复：绑定关键参数 + domain separation
        bytes32 digest = keccak256(
            abi.encode(
                "D40_TRANSFER_V1",
                block.chainid,
                address(this),
                from,
                to,
                amount,
                nonce,
                deadline
            )
        );

        address recovered = ecrecover(toEthSignedMessageHash(digest), v, r, s);
        if (recovered != from) revert BadSig();

        nonces[from] = nonce + 1;

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function toEthSignedMessageHash(bytes32 h) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }
}
```

---

## 6. 攻击测试与回归测试（Foundry）

文件建议：`labs/foundry-labs/test/vulns/D40_ParamInjection.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/vulns/D40_ParamInjectionVuln.sol";
import "../../src/fixed/D40_ParamInjectionFixed.sol";

contract D40_ParamInjection_Test is Test {
    D40_ParamInjectionVuln vuln;
    D40_ParamInjectionFixed fixedC;

    uint256 alicePk;
    address alice;
    address bob;
    address attacker;

    function setUp() public {
        vuln = new D40_ParamInjectionVuln();
        fixedC = new D40_ParamInjectionFixed();

        alicePk = 0xA11CE;
        alice = vm.addr(alicePk);
        bob = makeAddr("bob");
        attacker = makeAddr("attacker");

        vuln.mint(alice, 1000);
        fixedC.mint(alice, 1000);
    }

    // ✅ 漏洞复现：同一签名，攻击者注入 to/amount 盗走资产
    function test_vuln_paramInjection_stealsMoreAndChangesRecipient() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = vuln.nonces(alice);

        bytes32 digest = keccak256(
            abi.encodePacked("D40_TRANSFER_V1", alice, nonce, deadline)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, toEthSignedMessageHash(digest));

        // attacker 注入：to=attacker, amount=900
        vuln.transferWithSig(alice, attacker, 900, deadline, v, r, s);

        assertEq(vuln.balanceOf(attacker), 900);
        assertEq(vuln.balanceOf(alice), 100);
    }

    // ✅ 修复回归：注入失败（签名绑定了 to/amount + domain）
    function test_fixed_paramInjection_failsBecauseToAmountAreSigned() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = fixedC.nonces(alice);

        address intendedTo = bob;
        uint256 intendedAmount = 100;

        bytes32 digest = keccak256(
            abi.encode(
                "D40_TRANSFER_V1",
                block.chainid,
                address(fixedC),
                alice,
                intendedTo,
                intendedAmount,
                nonce,
                deadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, toEthSignedMessageHash(digest));

        // attacker 尝试注入：改 to/amount → BadSig
        vm.expectRevert(D40_ParamInjectionFixed.BadSig.selector);
        fixedC.transferWithSig(alice, attacker, 900, deadline, v, r, s);

        // 正常执行：必须与签名一致
        fixedC.transferWithSig(alice, intendedTo, intendedAmount, deadline, v, r, s);

        assertEq(fixedC.balanceOf(bob), 100);
        assertEq(fixedC.balanceOf(alice), 900);
    }

    function toEthSignedMessageHash(bytes32 h) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }
}
```

运行命令：

```bash
cd labs/foundry-labs
forge test --match-contract D40_ParamInjection_Test -vvv
```

---

## 7. 审计视角（Checklist）

### 7.1 必查：签名绑定是否完整
- [ ] `to` 是否纳入 digest？
- [ ] `amount`（或 shares/value）是否纳入 digest？
- [ ] 是否把“实际执行会影响资产/权限”的所有字段都签进去？
  - e.g. `token`, `spender`, `receiver`, `fee`, `salt`, `action`, `method`

### 7.2 必查：重放与过期
- [ ] 是否有 `nonce`（每次使用后递增/置位）？
- [ ] 是否有 `deadline`（过期即拒绝）？
- [ ] nonce 是否与 `from` 绑定（`nonces[from]`）？

### 7.3 必查：域隔离（domain separation）
- [ ] digest 是否包含 `chainId`？
- [ ] digest 是否包含 `verifyingContract`（`address(this)`)？
- [ ] 换链/换合约是否会导致签名失效（应该失效）？

### 7.4 必查：调用者与接收者关系
- [ ] 是否错误地假设 `msg.sender == to`？
- [ ] 是否允许任意 relayer 执行（允许的话更要绑定 `to`/`amount`）？
- [ ] 是否存在“签了给 bob，执行给 attacker”的路径？

### 7.5 推荐：使用 EIP-712 typed data
- [ ] 优先 EIP-712（结构化字段 + domain），降低 `abi.encodePacked` 拼接歧义风险
- [ ] 若使用 `abi.encodePacked`，确保字段类型边界清晰、不会拼接碰撞

---

## 8. 常见坑位总结

1) **漏签关键字段**：最常见、最致命（本题）  
2) **nonce 未做/不递增**：同签名可无限重放（关联 D37）  
3) **无 domain separation**：跨链/跨合约复用签名（关联 D38）  
4) **deadline 未校验**：签名永久有效，泄露即长期风险  
5) **`abi.encodePacked` 拼接歧义**：可导致哈希碰撞（建议 EIP-712）  

---

## 9. 本日产物清单（落库用）

- 📦 漏洞合约：`src/vulns/D40_ParamInjectionVuln.sol`
- ✅ 修复合约：`src/fixed/D40_ParamInjectionFixed.sol`
- 🧪 测试：`test/vulns/D40_ParamInjection.t.sol`
- ▶️ 运行：`forge test --match-contract D40_ParamInjection_Test -vvv`

---

## 10. 建议分支与提交信息

- 分支：`d40-param-injection-sig-mismatch`
- commit（单条）：`feat(d40): add param-injection vuln (sig omits to/amount) with fix and tests`
