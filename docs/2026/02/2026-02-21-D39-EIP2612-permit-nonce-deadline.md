# 2026-02-21 - D39：EIP-2612 permit（nonce / deadline）最小实现与测试（Foundry + OpenZeppelin）

tags: [eip2612, permit, eip712, signature, nonce, deadline, replay, foundry, forge, solidity, openzeppelin, audit]

## 背景 / 目标

传统 ERC20 授权通常需要两步：
1. `approve(spender, value)`（链上 1 笔交易，写入 allowance）
2. `spender` 再执行 `transferFrom(...)`（链上 1 笔交易，实际花钱/转账）

EIP-2612 `permit` 的目标是把第 1 步「链上 approve」替换为「链下签名」，再由任意提交者把签名递交上链完成授权，从而在常见场景（如 DEX 一键操作）把 **首次授权 + 消费** 从 **2 笔交易** 合并为 **1 笔交易**。

本日交付：
- ✅ 一个最小可用的 `ERC20Permit` token（OpenZeppelin）
- ✅ Foundry 测试覆盖：正常 permit、生效的 nonce、防重放、deadline 过期
- ✅ 审计视角 checklist
- ✅ 把你在学习中问到的问题也写入本文（“多发一笔交易体现在哪里？”、“constructor 为什么写在大括号前？”）

---

## 核心概念（通俗易懂）

### 1）permit 是什么？

`permit` 是一种“**链下签名授权、链上验证落库**”的机制。

- Owner 在链下签一份“授权书”（不花 gas）
- 任何人都可以把这份签名提交到链上调用 `permit(...)`
- 合约会验证签名确实来自 owner，且没过期、没被用过
- 验证通过后，合约在链上更新 allowance（等价于 approve）

### 2）nonce 做什么？为什么能防重放？

每个 owner 都有一个 `nonces[owner]`（授权计数器）：

- permit 消息中包含 nonce
- permit 成功后 nonce 会 **+1**
- 同一份签名只能用一次：重放时 nonce 已变化 → digest 不一致 → 验签失败

一句话记忆：**nonce = 一次性编号**，用于抵抗“重复使用同一个签名”的重放攻击。

### 3）deadline 做什么？

permit 消息里包含 deadline（有效期）：

- 若 `block.timestamp > deadline`，permit 必须失败
- 避免旧签名长期有效，未来被翻出来利用

一句话记忆：**deadline = 签名过期时间**。

### 4）EIP-712 与 domain separation（域隔离）

permit 使用 EIP-712（结构化签名）：
- 结构化内容：`owner, spender, value, nonce, deadline`
- 域信息（domain）：通常包含 `name, version, chainId, verifyingContract`

域隔离的意义：
- 防止把同一份签名拿到“别的合约/别的链”上复用（跨合约/跨链重放风险降低）

---

## 你问到的问题（写进文档便于复习）

### Q1：**“多发一笔交易”体现在哪里？**

体现在 **传统模式下必须单独发一笔 `approve` 交易**。

以“USDC 换 ETH”为例：

**没有 permit：**
1. 交易 #1：`USDC.approve(router, amountIn)`（写 allowance，付 gas）
2. 交易 #2：`router.swapExactTokensForTokens(...)`（内部 `transferFrom`，再付 gas）

**有 permit：**
- 你先链下签名（不算交易，0 gas）
- 只发 **1 笔交易**（swap 交易），在这笔交易中 router 先调用 `permit` 写 allowance，再立刻 `transferFrom` 消费

所以“多一笔”就是：**为了授权 allowance，多了一笔单独的 approve 上链交易**（首次与某个 spender 交互时最明显）。

> 注：如果你之前已经做过 max approve（无限授权），后续 swap 可能也只要 1 笔交易，但那是因为你提前付过那次授权成本。

---

### Q2：**constructor 为什么要写 `ERC20(name_, symbol_) ERC20Permit(name_)` 在大括号前？能不能写到 `{}` 里面？**

这是 Solidity 的**父合约构造函数初始化列表（base constructor initializer list）**语法。

当你的合约继承了带构造函数参数的父合约（这里是 `ERC20` 与 `ERC20Permit`）时：
- 父合约必须在子合约构造函数体 `{}` 执行前初始化完成
- 所以父构造函数的参数必须写在 `{}` 前面

下面是正确写法：

```solidity
constructor(string memory name_, string memory symbol_)
    ERC20(name_, symbol_)
    ERC20Permit(name_)
{}
```

你可以在 `{}` 里写“普通逻辑”，比如 mint 初始余额等，但不能把父构造函数当作普通函数调用放进去。

另外：
- `ERC20Permit(name_)` 只需要 `name`（用于 EIP-712 domain），symbol 不属于 EIP-2612 domain 的必需字段；OpenZeppelin 也是按标准实现。

---

## 实现步骤（建议落地路径）

### Step 0：创建分支

```bash
git checkout -b d39-eip2612-permit
```

### Step 1：新增合约（OpenZeppelin 版）

建议路径：`labs/foundry-labs/src/erc20/PermitERC20.sol`

### Step 2：新增测试

建议路径：`labs/foundry-labs/test/erc20/PermitERC20.permit.t.sol`

### Step 3：运行测试

```bash
cd labs/foundry-labs
forge test --match-contract PermitERC20_PermitTest -vvv
```

---

## 参考代码

### 1）合约：PermitERC20.sol（OpenZeppelin ERC20Permit）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract PermitERC20 is ERC20, ERC20Permit {
    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        ERC20Permit(name_) // EIP-712 domain 的 name
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
```

---

### 2）测试：PermitERC20.permit.t.sol（成功 / 重放 / 过期）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {PermitERC20} from "../../src/erc20/PermitERC20.sol";

contract PermitERC20_PermitTest is Test {
    PermitERC20 token;

    uint256 ownerPk;
    address owner;

    address spender = makeAddr("spender");

    function setUp() public {
        token = new PermitERC20("PermitToken", "PTK");

        ownerPk = 0xA11CE; // 测试私钥
        owner = vm.addr(ownerPk);

        token.mint(owner, 1_000 ether);
    }

    function test_permit_success_setsAllowance_andIncrementsNonce() public {
        uint256 value = 123 ether;
        uint256 deadline = block.timestamp + 1 days;

        uint256 nonceBefore = token.nonces(owner);

        bytes32 digest = _permitDigest(owner, spender, value, nonceBefore, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        token.permit(owner, spender, value, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), value);
        assertEq(token.nonces(owner), nonceBefore + 1);
    }

    function test_permit_replay_sameSignature_reverts_dueToNonce() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 days;

        uint256 nonceBefore = token.nonces(owner);

        bytes32 digest = _permitDigest(owner, spender, value, nonceBefore, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        token.permit(owner, spender, value, deadline, v, r, s);
        assertEq(token.allowance(owner, spender), value);

        // 重放同签名：nonce 已变化 → 应 revert
        vm.expectRevert();
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    function test_permit_deadlineExpired_reverts() public {
        uint256 value = 5 ether;
        uint256 deadline = block.timestamp + 10;

        uint256 nonceBefore = token.nonces(owner);

        bytes32 digest = _permitDigest(owner, spender, value, nonceBefore, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        vm.warp(deadline + 1);

        vm.expectRevert();
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    // --- helper：按 EIP-712 拼出 digest ---
    function _permitDigest(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _nonce,
        uint256 _deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                _owner,
                _spender,
                _value,
                _nonce,
                _deadline
            )
        );

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
```

---

## 审计视角（Checklist）

### A. 重放与一次性使用
- [ ] `nonces[owner]` 是否在 **permit 成功后递增**？
- [ ] 是否存在“签名可多次使用”的路径（如 nonce 不变、或把 nonce 放错字段）？

### B. 过期与授权窗口
- [ ] 是否校验 `block.timestamp <= deadline`？
- [ ] deadline 是否可能被绕过（比如 0 被当作永久有效）？是否符合业务预期？

### C. 域隔离（跨链/跨合约）
- [ ] EIP-712 domain 是否包含 `chainId` 与 `verifyingContract`？
- [ ] token 的 `name`/`version` 是否稳定一致，避免意外的 domain 变化导致签名不可用或复用风险？

### D. 签名验证正确性
- [ ] 是否使用成熟的 ECDSA 实现（OpenZeppelin）避免 `s` malleability / `v` 值等细节坑？
- [ ] 是否正确恢复 signer 并与 `owner` 比对？

### E. 与业务动作组合（Permit + Action）
- [ ] Router/合约把 permit 与 `transferFrom` 合并时，spender 是否可被第三方替换？（授权意图要明确）
- [ ] 是否存在“授权给意外 spender”的 UX 风险（比如签名展示不清晰）？

---

## 运行指令速记

```bash
cd labs/foundry-labs
forge test --match-contract PermitERC20_PermitTest -vvv
```

---

## 今日小结

- permit 把“approve 交易”变成“链下签名”，可将常见首次交互从 2 笔交易合并成 1 笔交易（permit + transferFrom）。
- nonce 负责一次性使用，deadline 负责有效期；EIP-712 domain 负责跨链/跨合约隔离。
- OpenZeppelin 的 `ERC20Permit` 是推荐实现，减少自写 `ecrecover` 细节风险。
