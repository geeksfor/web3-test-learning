# ERC-721 / ERC-20 学习笔记（基于本次问答）
> 用途：复习 ERC-721 Receiver、安全转账授权逻辑、Foundry 测试与 Invariant/Fuzz Handler 写法等。

tags: [solidity, erc721, erc20, foundry, fuzz, invariant, testing]

---

## 1. IERC721Receiver 接口是 Solidity 语法吗？

是的，这是 **Solidity 的 interface 语法**。接口里只声明函数签名，不提供实现：

- `interface IERC721Receiver { ... }`：声明接口
- `external`：外部可调用
- `returns (bytes4)`：返回 4 字节值（函数选择器）
- `bytes calldata data`：外部输入数据，位于 `calldata`（只读，通常更省 gas）

---

## 2. 为什么一定要返回 bytes4？返回值具体是什么？

### 2.1 为什么需要返回值（安全转账握手）
ERC-721 的 `safeTransferFrom` 在 `to` 是合约地址时，会回调：

- `onERC721Received(...)`

用返回值确认“接收方合约明确支持 ERC-721 并愿意接收”，否则交易 revert，防止 NFT 被转入 **不支持 NFT 的合约**而永久锁死。

### 2.2 返回值是什么
标准要求返回：

- `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))` 的前 4 字节
- 等价写法：`IERC721Receiver.onERC721Received.selector`
- 常见常量：`0x150b7a02`

---

## 3. onERC721Received 的 4 个参数含义

函数签名：

```solidity
onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
```

- `operator`：**操作者**（通常是 `msg.sender`，即谁调用了 NFT 合约的 `safeTransferFrom`）  
  - 用户自己转：operator == from  
  - 市场/代理合约代转：operator 是市场合约，from 是真实 owner

- `from`：**原持有人**（转出方，转账前 token 的 owner）

- `tokenId`：**NFT 唯一编号**

- `data`：额外附带数据（payload），可为空，用于接收方扩展逻辑（例如携带订单号、仓位信息等）。注意接收方应结合 `operator/from` 做校验，避免被恶意构造数据。

---

## 4. ERC-721 两种授权字段的含义

### 4.1 `tokenApprovals[tokenId]`
**单个 tokenId 的授权**（approve）：

- `approve(to, tokenId)` 写入 `tokenApprovals[tokenId] = to`
- 仅对该 tokenId 生效
- 通常在转账/销毁时清空（避免旧授权影响新 owner）

### 4.2 `_operatorApprovals[owner][operator]`
**全量授权**（setApprovalForAll）：

- `setApprovalForAll(operator, true)` 写入 `_operatorApprovals[owner][operator] = true`
- operator 可操作 owner 名下所有 token
- 通常不会在转账时清空（这是 owner 级别的长期设置）

---

## 5. 为什么转账时清 tokenApprovals，但不清 operatorApprovals？

你看到的逻辑：

```solidity
if (_tokenApprovals[tokenId] != address(0)) {
    _tokenApprovals[tokenId] = address(0);
    emit Approval(owner, address(0), tokenId);
}
```

原因：

- `tokenApprovals[tokenId]` 是 **绑定在某个 tokenId 上的临时授权**  
  token 换 owner 后必须清掉，否则可能出现：旧 owner 授权过的人仍能转走新 owner 的 NFT（严重安全问题）。

- `_operatorApprovals[owner][operator]` 是 **owner 级别的长期授权**  
  即使原 owner 把某个 token 转走，operator 授权也只对原 owner 仍持有的 token 生效，不会“继承”到新 owner，所以无需在每次 transfer 时清除。

---

## 6. 为什么 safeTransferFrom 常写成 public？

`safeTransferFrom` 至少要对外可调用（`public` 或 `external` 都可以）。
很多实现选择 `public` 的常见原因：

- 方便合约内部调用（尤其是两个重载之间互相调用）
- 内部调用不会变成 `this.xxx()` 的外部调用，gas 更省
- 关键：内部调用能保持 `msg.sender` 不变（授权逻辑依赖 `msg.sender`）

更偏工程化的写法通常是：外部 `external`（用 `calldata`），内部实现抽到 `_safeTransfer(...)`。

---

## 7. `to.code.length` 为什么是 `to.code`？

`to` 是 `address`，Solidity 提供 `address.code` 语法糖，表示该地址的 **运行时代码（runtime bytecode）**：

- `to.code.length == 0`：通常是 EOA 或合约正在构造中/已 selfdestruct
- `to.code.length > 0`：已部署合约地址

ERC-721/1155 用它判断：如果接收方是合约，就必须调用 `onERC721Received` 进行安全接收检查。

注意：构造期间 code.length 可能为 0，因此不适合当作“是否可信合约”的强安全判断。

---

## 8. 为什么测试里要验证 `assertEq(getApproved(tokenId), address(0))`？

示例断言：

```solidity
assertEq(nft.getApproved(1), address(0));
```

目的：验证 **单 token 授权在转账后被清空**。

否则会出现安全问题：旧 owner 之前批准的 `approved` 地址可能在转账后仍能操作该 token，导致新 owner 的 NFT 被转走。

该断言能防止“只测转账成功但漏掉授权清理”的隐蔽 bug。

---

## 9. transferFrom 的 revert：NotOwnerNorApproved vs InvalidFrom

你贴的代码顺序：

```solidity
address owner = ownerOf(tokenId);
if (owner != from) revert InvalidFrom();
```

因此：

- 只要 `from` 参数不是当前 owner，会 **优先**触发 `InvalidFrom()`（甚至还没检查 msg.sender 权限）。
- 若测试用例名是 `reverts_ifNotOwnerNorApproved`，通常应确保：
  - `from` 写对（等于真实 owner）
  - `msg.sender` 不具备 owner/approve/operator 权限  
  才会触发“权限不足”类错误。

结论：要匹配预期 revert，需要让测试输入满足对应分支前置条件，并关注你合约里的检查顺序。

---

## 10. 为什么 ERC-20 没有“转账时清空授权”？

对比核心差异：

- ERC-721 `approve(tokenId)`：对 **唯一资产 tokenId** 的单独授权，所有权变化必须清空，否则会影响新 owner。
- ERC-20 allowance：是 **额度模型（credit line）**，设计就是支持多次消费：  
  `transferFrom` 成功后通常是 `allowance -= amount`，而不是一转账就归零。
  否则 DeFi/订阅/分期等场景会变得不可用（每次都要重新 approve）。

另外 ERC-20 有著名的 approve 竞态问题，常用 `increaseAllowance/decreaseAllowance` 或先置 0 再设置解决，但不是靠“自动清空授权”解决。

---

## 11. 为什么 `expectRevert(SimpleERC721.UnsafeRecipient.selector)` 这么写？

合约里触发：

```solidity
revert UnsafeRecipient();
```

Foundry 的 `vm.expectRevert(...)` 通常传的是 **错误选择器 selector（bytes4）**：

- `UnsafeRecipient.selector` 需要能在测试作用域解析到该 error 类型
- 常见稳妥写法：`SimpleERC721.UnsafeRecipient.selector`（明确这个 error 定义在哪个合约里，避免作用域/同名冲突）

如果 error 有参数，通常用：

```solidity
vm.expectRevert(abi.encodeWithSelector(SimpleERC721.SomeError.selector, arg1, arg2));
```

---

## 12. Foundry Handler + targetContract：mintRandom 没显式调用，为什么会执行？

你给的 Handler：

```solidity
contract ERC721MintRandomHandler is Test {
    SimpleERC721 public nft;
    address public target;

    mapping(uint256 => bool) public minted;
    uint256 public mintedCount;

    constructor(SimpleERC721 _nft, address _target) {
        nft = _nft;
        target = _target;
    }

    function mintRandom(uint256 tokenId) external {
        tokenId = bound(tokenId, 1, 1_000_000);
        vm.assume(!minted[tokenId]);
        nft.mint(target, tokenId);
        minted[tokenId] = true;
        mintedCount++;
    }
}
```

测试 setUp：

```solidity
handler = new ERC721MintRandomHandler(nft, alice);
targetContract(address(handler));
```

断言：

```solidity
assertEq(nft.balanceOf(alice), handler.mintedCount());
```

解释：

- `targetContract(address(handler))` 表示把 handler 注册成 **stateful fuzz / invariant** 的目标合约。
- Foundry 在跑 `invariant_*` 测试时，会在每轮 invariant 检查之前，随机选择 target 合约的外部函数（这里就是 `mintRandom`）并用随机参数调用多次。
- 所以你看不到测试里显式调用，但 `mintRandom` 确实被 Foundry 自动调用，从而 `mintedCount` 与 `balanceOf(alice)` 一起增长。

你可用 `forge test -vvv` + 事件/console log 来观察调用轨迹。

---

## 复习清单（快速自测）
- ERC-721 safeTransfer 的“握手”为什么要返回 selector？返回哪个 selector？
- `approve(tokenId)` 为什么必须在 transfer 时清空？
- `setApprovalForAll` 为什么不清？为什么不会影响新 owner？
- `to.code.length` 能判断什么？有哪些场景会误判？
- Foundry 的 `targetContract(handler)` 会触发什么测试模式？函数在哪被调用？
- `vm.expectRevert(Error.selector)` 的 selector 从哪里来？为什么要加 `ContractName.` 前缀？

---

> 备注：如果你后续把 SimpleERC721 的完整实现贴出来，可以把这份笔记升级成“基于你的源码的逐行注释版”。
