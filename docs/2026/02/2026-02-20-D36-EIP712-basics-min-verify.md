# 2026-02-20 - D36 | EIP-712 基础：domain separator、typed data；最小 verify 合约 + 正常验签测试

tags: [solidity, eip712, signature, ecdsa, foundry, forge, security]

## 背景 / 目标

今天目标是把 **EIP-712（结构化签名）** 的核心链路跑通，并能解释它与“交易签名”、以及你之前 D35/D31~D33 的 `messageId` 防重放的区别与联系：

- 理解：`domain separator`（域分离）、`typed data`（结构化数据）、`TYPEHASH`、`structHash`、最终 `digest`
- 实现：最小 `verify` 合约（链上验签）
- 测试：Foundry 正常验签（happy path）+ 常见负例（deadline/nonce/signer）
- 补齐：审计视角 Checklist（如何避免重放、域混淆、签名可塑性等坑）

---

## 一、EIP-712 用人话解释

### 1.1 EIP-712 解决什么问题？

你可以把 EIP-712 当成：**“链下签一张结构化授权书，然后把授权书带上链，由合约验真伪”**。

它主要解决：

1) **用户能看懂自己签了什么**  
钱包可以按字段展示（to/amount/deadline…），减少“盲签”。

2) **域隔离（防跨链/跨合约复用）**  
把 `chainId` 与 `verifyingContract`（验签合约地址）放进 domain，让签名只在特定链、特定合约下有效。

3) **结构化编码一致**  
用 `TYPEHASH + abi.encode(...)` 约束“字段类型 + 顺序”，避免同样的 bytes 被不同含义解释。

---

## 二、两层哈希：structHash 与 digest

EIP-712 核心分两步：

### 2.1 structHash（只针对结构体）

对某个结构体（如 `Mail`）的具体字段值做哈希：

- 先固定结构体“模板 ID”：`MAIL_TYPEHASH`
- 再把模板 + 字段值 `abi.encode` 后 `keccak256`

得到的就是 `structHash`。

### 2.2 digest（最终被签名/验签的哈希）

最终签名/验签的 digest 是：

`digest = keccak256( "\x19\x01" || DOMAIN_SEPARATOR || structHash )`

其中：

- `DOMAIN_SEPARATOR`：域（name/version/chainId/verifyingContract）的指纹
- `structHash`：结构体内容的指纹
- `\x19\x01`：EIP-712 的固定前缀（域分离用，避免与其它签名格式混淆）

---

## 三、最小实现（合约 + 测试）

### 3.1 合约：`src/eip712/D36_MinEIP712Verifier.sol`

> 目标：提供 `digestMail()` 与 `verify()`，把 EIP-712 的 digest 算对，并能 recover 出 signer。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract D36_MinEIP712Verifier {
    // --- EIP-712 domain ---
    bytes32 public constant EIP712DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public immutable NAME_HASH;
    bytes32 public immutable VERSION_HASH;

    // --- Typed data: Mail ---
    bytes32 public constant MAIL_TYPEHASH =
        keccak256("Mail(address to,uint256 amount,uint256 nonce,uint256 deadline)");

    struct Mail {
        address to;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
    }

    constructor(string memory name, string memory version) {
        NAME_HASH = keccak256(bytes(name));
        VERSION_HASH = keccak256(bytes(version));

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                NAME_HASH,
                VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    // 只算结构体 hash（structHash）
    function hashMail(Mail memory m) public pure returns (bytes32) {
        return keccak256(abi.encode(MAIL_TYPEHASH, m.to, m.amount, m.nonce, m.deadline));
    }

    // 算最终 digest（签名/验签用）
    function digestMail(Mail memory m) public view returns (bytes32) {
        bytes32 structHash = hashMail(m);
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    // 最小验签：可按需要加入 nonce/额度/白名单等业务校验
    function verify(address expectedSigner, Mail memory m, uint8 v, bytes32 r, bytes32 s)
        public
        view
        returns (bool)
    {
        if (block.timestamp > m.deadline) return false;

        bytes32 digest = digestMail(m);
        address recovered = ecrecover(digest, v, r, s);
        return recovered == expectedSigner && recovered != address(0);
    }
}
```

---

### 3.2 测试：`test/eip712/D36_MinEIP712Verifier.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../../src/eip712/D36_MinEIP712Verifier.sol";

contract D36_MinEIP712Verifier_Test is Test {
    D36_MinEIP712Verifier verifier;

    uint256 signerPk;
    address signer;

    address bob = address(0xB0B);

    function setUp() public {
        verifier = new D36_MinEIP712Verifier("D36-MinEIP712", "1");

        signerPk = 0xA11CE;          // 测试专用私钥
        signer   = vm.addr(signerPk); // 从私钥推导地址
    }

    function test_verify_ok() public {
        D36_MinEIP712Verifier.Mail memory m = D36_MinEIP712Verifier.Mail({
            to: bob,
            amount: 123,
            nonce: 1,
            deadline: block.timestamp + 1 hours
        });

        bytes32 digest = verifier.digestMail(m);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        bool ok = verifier.verify(signer, m, v, r, s);
        assertTrue(ok);
    }

    function test_verify_fails_if_deadline_expired() public {
        D36_MinEIP712Verifier.Mail memory m = D36_MinEIP712Verifier.Mail({
            to: bob,
            amount: 123,
            nonce: 1,
            deadline: block.timestamp + 1
        });

        bytes32 digest = verifier.digestMail(m);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        vm.warp(block.timestamp + 2);
        assertFalse(verifier.verify(signer, m, v, r, s));
    }

    function test_verify_fails_if_nonce_changed() public {
        D36_MinEIP712Verifier.Mail memory m = D36_MinEIP712Verifier.Mail({
            to: bob,
            amount: 123,
            nonce: 1,
            deadline: block.timestamp + 1 hours
        });

        bytes32 digest = verifier.digestMail(m);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        // 改 nonce 会改变 structHash/digest -> recover 不再匹配
        D36_MinEIP712Verifier.Mail memory m2 = D36_MinEIP712Verifier.Mail({
            to: bob,
            amount: 123,
            nonce: 2,
            deadline: m.deadline
        });

        assertFalse(verifier.verify(signer, m2, v, r, s));
    }

    function test_verify_fails_if_expectedSigner_wrong() public {
        D36_MinEIP712Verifier.Mail memory m = D36_MinEIP712Verifier.Mail({
            to: bob,
            amount: 123,
            nonce: 1,
            deadline: block.timestamp + 1 hours
        });

        bytes32 digest = verifier.digestMail(m);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        address attacker = address(0xBAD);
        assertFalse(verifier.verify(attacker, m, v, r, s));
    }
}
```

### 3.3 运行

```bash
cd labs/foundry-labs
forge test --match-contract D36_MinEIP712Verifier_Test -vvv
```

---

## 四、把你今天问过的问题串起来（Q&A）

### Q1：链下签名（EIP-712）与 D35 `messageId` 防重放有什么区别和联系？

- **messageId 防重放（D35）**：在“跨链消息接收/执行”层面，防同一条消息被重复投递/重复处理（`processed[messageId]`）。  
- **EIP-712 防重放**：在“授权/意图”层面，防同一份授权被重复使用（依赖 `nonce/deadline` 之类字段 + 合约验证）。  
- **联系**：本质都是“把上下文哈希进唯一标识里做域隔离”。实战常见两层一起用：消息层（messageId）+ 授权层（EIP-712 nonce）。

### Q2：链上验签发生在交易流程哪一步？EIP-712 又在哪一步签名？

- **EIP-712 签名**：链下（发交易前，钱包对 typed data digest 签名）  
- **链上验签**：交易被打包后，EVM 执行合约函数时（执行到 `ecrecover/ECDSA.recover` 的那一刻）

### Q3：授权意图是什么？一定是授权给其他人吗？

“授权意图”就是签名者同意某个动作发生（如转账/permit/订单成交/跨链 mint）。  
不一定指定某个人；有两类：
- **授权某人执行**：typed data 里包含 executor/relayer/spender，并校验 `msg.sender`  
- **授权执行某动作（谁提交都行）**：不绑定执行者，但要绑定参数 + nonce/deadline 防重放

### Q4：交易本身签名 vs EIP-712 签名（通俗解释）

- **交易签名**：证明“这笔交易由谁发起”（网络/节点层验证，带账户 nonce，通常由发交易的人付 gas）  
- **EIP-712 签名**：证明“某个账户同意/授权某个动作”（合约自己验证，可让第三方 relayer 代付 gas）

### Q5：这些声明是做什么？为什么要这么多？

```solidity
bytes32 public constant EIP712DOMAIN_TYPEHASH = keccak256("EIP712Domain(...)");
bytes32 public immutable DOMAIN_SEPARATOR;
bytes32 public immutable NAME_HASH;
bytes32 public immutable VERSION_HASH;
bytes32 public constant MAIL_TYPEHASH = keccak256("Mail(...)");
```

- `EIP712DOMAIN_TYPEHASH`：Domain 结构体的“模板 ID”（只描述格式，不含具体值）  
- `NAME_HASH/VERSION_HASH`：对 string 先 hash，符合 EIP-712 编码规则，也省 gas  
- `DOMAIN_SEPARATOR`：把模板 + 具体值（name/version/chainId/verifyingContract）编码 hash 得到域指纹  
- `MAIL_TYPEHASH`：Mail 结构体的模板 ID（保证字段类型/顺序固定）

> 只有模板（TYPEHASH）没法隔离域；必须算出 DOMAIN_SEPARATOR，签名才“只在某链某合约有效”。

### Q6：`hashMail()` 看起来只算了 Mail 的 hash ——对吗？

对。`hashMail()` 只算 `structHash`。  
真正用于签名/验签的是：`digest = keccak256("\x19\x01" || DOMAIN_SEPARATOR || structHash)`。

### Q7：为什么要加 `\x19\x01`？代表什么？

它是 EIP-712 固定前缀，用于“域分离”与“格式区分”：  
告诉系统这是 **EIP-712 typed data**，避免与其它签名格式（例如 personal_sign 的 `\x19Ethereum Signed Message...`）混淆。

### Q8：`ecrecover` 没声明就能直接用？是什么意思？

`ecrecover` 是 Solidity/EVM 内置能力（底层对应 ECRecover 预编译），可直接调用：  
`address recovered = ecrecover(digest, v, r, s);`

失败时常返回 `address(0)`，因此通常要检查 `recovered != address(0)`。

### Q9：你提到的“签名可塑性（malleability）”是什么意思？

同一条消息可能存在两份不同 `(r,s)` 都有效（常见形式：`(r, s)` 与 `(r, n-s)`）。  
如果你用“签名 bytes 自身”做防重放 key，可能被变形签名绕过。  
推荐用 nonce/messageId 做防重放，并在验签时做 **low-s** 检查（OpenZeppelin `ECDSA.recover` 默认处理）。

### Q10：`signerPk` / `signer` 是什么？

- `signerPk`：测试用私钥（只用于 `vm.sign` 生成签名）  
- `signer`：由私钥推导出来的地址（用于断言 recover 结果）

### Q11：`(v,r,s) = vm.sign(...)` 里的 v/r/s 分别是什么？

- `r`、`s`：ECDSA 签名的两个 32 字节大数（签名主体）  
- `v`：恢复标志（recovery id），帮助从签名恢复出正确的公钥/地址（常见 27/28 或 0/1）

---

## 五、审计视角 Checklist（建议你以后看到签名就照着扫）

### 5.1 域隔离（Domain）
- [ ] `DOMAIN_SEPARATOR` 是否包含 `chainId` + `verifyingContract`（防跨链/跨合约复用）
- [ ] `name/version` 是否固定且有意义（升级/多版本并存时很重要）
- [ ] 前端 typed data domain 与合约是否完全一致（最常见踩坑）

### 5.2 消息防重放（Message / Nonce）
- [ ] typed data 是否包含 `nonce`（或等价唯一值）
- [ ] 合约是否维护并更新 `nonces[signer]`（一旦通过立刻递增/标记）
- [ ] 是否包含 `deadline` 并强制检查（减少泄露后的长期风险）
- [ ] 不要用“签名 bytes”本身当防重放 key（会被 malleability 绕过）

### 5.3 验签健壮性（ECDSA）
- [ ] 是否使用 OpenZeppelin `ECDSA.recover`（处理 low-s、v 兼容等）
- [ ] 如果用 `ecrecover`：是否校验 `recovered != address(0)`、`v` 范围、`s` low-half
- [ ] 是否明确绑定执行者（可选）：需要时加 `executor/relayer` 字段并校验 `msg.sender`

### 5.4 业务语义绑定（避免“签名被挪用”）
- [ ] typed data 中是否包含关键参数：`to/amount/token/chainId/bridgeId/...`
- [ ] 是否包含“用途/动作类型”（例如 `action` 或 `purpose`），避免同一签名在另一接口被复用
- [ ] 是否对 payload 做完整绑定（避免只签部分字段导致“换参攻击”）

---

## 六、分支与提交信息（建议）

- 分支：`d36-eip712-basics-min-verify`
- commit（示例）：
  - `feat(d36): add minimal EIP-712 verifier and signature verification tests`

---

## 七、后续可选增强（不影响 D36 最小闭环）

1) 用 OpenZeppelin `ECDSA.recover` 替换 `ecrecover`（加入 low-s 检查）  
2) 增加 `nonces[signer]` 的状态更新，做“成功一次后同签名必失败”的重放测试  
3) 加一个 `executor` 字段，演示“限定谁能提交签名”（防别人抢跑/滥用）
