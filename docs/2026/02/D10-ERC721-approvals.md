# 2026-02-05 - D10：ERC721 授权体系测试（approvalForAll / tokenApproval）

tags: [foundry, forge, solidity, erc721, testing, approvals]

## 背景 / 目标
今天目标是把 **ERC721 的两类授权**测全并理解清楚它们的语义与联动：

1) **tokenApproval（approve / getApproved）**：对“单个 tokenId”授权给某个地址  
2) **operatorApproval（setApprovalForAll / isApprovedForAll）**：对“某个 operator”授权，使其可操作你名下**全部** token

最终做到：
- 授权/取消授权的 **状态正确**
- 对应 **事件（Approval / ApprovalForAll）** 正确
- 授权后可执行 **transferFrom/safeTransferFrom**
- 转移后 **tokenApproval 会自动清空**
- 常见 **revert 分支**覆盖齐（不存在 token、无权限、授权给自己等）

---

## 今日完成清单（Checklist）
- [ ] 写 `setApprovalForAll` 授权/取消授权测试
- [ ] 写 `approve` 授权测试（owner 与 operator 均可）
- [ ] 写 `approve` 无权限 / token 不存在 / 授权给 owner 等 revert 测试
- [ ] 写 “被 approve 的地址可以 transferFrom/safeTransferFrom” 测试
- [ ] 写 “转移后 getApproved(tokenId) 清空” 测试
- [ ] 补：`getApproved(nonexistent)` revert 测试（如果你的实现符合标准）

---

## 核心概念梳理

### 1）setApprovalForAll 是谁来调用的？
一般是 **token 的 owner（持有人）**自己调用，用来把“操作我名下所有 NFT 的权限”授权给第三方 operator（常见：NFT 市场合约、聚合器、借贷/租赁协议、代理钱包/多签等）。

> 该函数只影响 `_operatorApprovals[msg.sender][operator]`，因此不需要“NotOwnerNorApproved”校验；权限校验应该出现在 `approve/transferFrom/safeTransferFrom` 等**针对 tokenId 的操作**里。

### 2）两种授权的区别
- `approve(to, tokenId)`：只授权 **一个 tokenId**
- `setApprovalForAll(operator, true)`：授权 **operator** 可操作你名下 **所有 tokenId**

### 3）谁能转走 token？
典型的 ERC721 权限判断（推荐抽为 `_isApprovedOrOwner`）：

- `msg.sender == owner`（本人）
- `msg.sender == getApproved(tokenId)`（单 token 授权）
- `isApprovedForAll(owner, msg.sender)`（operator 授权）

---

## 你的合约片段点评

### setApprovalForAll（你的实现）
```solidity
function setApprovalForAll(address operator, bool approved) external {
    if (msg.sender == operator) revert ApproveToSelf();
    _operatorApprovals[msg.sender][operator] = approved;
    emit ApprovalForAll(msg.sender, operator, approved);
}
```

**结论：这个函数本身不需要加你说的那种权限校验。**  
因为它只允许调用者为“自己”设置 operator，永远不会影响别人的 token 权限。

你提到的：
```solidity
if (msg.sender != owner && !_operatorApprovals[owner][msg.sender]) revert NotOwnerNorApproved();
```
应放在 `approve/transferFrom/safeTransferFrom` 等**token 相关操作**里，而不是 setApprovalForAll。

---

## 测试用例设计（建议按这个顺序写）

> 假设地址：  
> `alice` = owner  
> `bob` = 被授权者 / 接收者  
> `op` = operator  
> `stranger` = 无权限者  
> `tokenId = 1`

### A. setApprovalForAll / isApprovedForAll
1. **授权成功**
   - `alice` 调用 `setApprovalForAll(op, true)`
   - 断言 `isApprovedForAll(alice, op) == true`
   - 校验事件 `ApprovalForAll(alice, op, true)`

2. **取消授权成功**
   - 在已授权的前提下，`alice` 调用 `setApprovalForAll(op, false)`
   - 断言 `isApprovedForAll(alice, op) == false`
   - 校验事件 `ApprovalForAll(alice, op, false)`

3. **不能给自己授权（revert）**
   - `alice` 调用 `setApprovalForAll(alice, true)` 应 revert `ApproveToSelf`

### B. approve / getApproved
4. **owner 对单 token 授权成功**
   - `alice` 调用 `approve(bob, tokenId)`
   - 断言 `getApproved(tokenId) == bob`
   - 校验事件 `Approval(alice, bob, tokenId)`

5. **operator 也能对单 token 授权（前提：approvalForAll）**
   - `alice` 先 `setApprovalForAll(op, true)`
   - `op` 调用 `approve(bob, tokenId)` 成功
   - 断言 `getApproved(tokenId) == bob`

6. **无权限 approve（revert）**
   - `stranger` 调用 `approve(bob, tokenId)` 应 revert `NotOwnerNorApproved`

7. **approve 不存在的 tokenId（revert）**
   - `approve(bob, 999)` 应 revert（通常是 `TokenNotMinted`/`NonexistentToken`）

8. **getApproved 不存在的 tokenId（revert）**
   - `getApproved(999)` 应 revert（如果你的实现遵循标准）

9. **approve 给 owner 自己（revert）**
   - `alice` 调用 `approve(alice, tokenId)` 应 revert（标准要求拒绝）

### C. 授权与转移联动
10. **被 approve 的 bob 可以 transferFrom**
   - `alice` `approve(bob, tokenId)`
   - `bob` `transferFrom(alice, bob, tokenId)` 成功
   - 断言 `ownerOf(tokenId) == bob`

11. **转移后 tokenApproval 被清空**
   - 在 10 的基础上：断言 `getApproved(tokenId) == address(0)`

12. **operator 可以 transferFrom（approvalForAll）**
   - `alice` `setApprovalForAll(op, true)`
   - `op` `transferFrom(alice, bob, tokenId)` 成功

13. **取消 operator 后再转应 revert**
   - `alice` `setApprovalForAll(op, false)`
   - `op` 再尝试 `transferFrom` 应 revert `NotOwnerNorApproved`

---

## Foundry 测试代码模板（可直接套用）

> 注意：下面 selector / error 名需要你按实际合约调整。

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleERC721.sol";

contract SimpleERC721ApprovalsTest is Test {
    SimpleERC721 nft;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address op    = address(0x0B0B0B);  // 示例地址：换成你喜欢的
    address stranger = address(0xBAD);

    uint256 tokenId = 1;

    function setUp() public {
        nft = new SimpleERC721();
        nft.mint(alice, tokenId);
    }

    // A1: setApprovalForAll true
    function test_setApprovalForAll_true_setsState_andEmits() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ApprovalForAll(alice, op, true);
        nft.setApprovalForAll(op, true);

        assertTrue(nft.isApprovedForAll(alice, op));
    }

    // A3: setApprovalForAll self revert
    function test_setApprovalForAll_self_reverts() public {
        vm.prank(alice);
        vm.expectRevert(SimpleERC721.ApproveToSelf.selector);
        nft.setApprovalForAll(alice, true);
    }

    // B4: owner approve
    function test_approve_owner_setsGetApproved_andEmits() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Approval(alice, bob, tokenId);
        nft.approve(bob, tokenId);

        assertEq(nft.getApproved(tokenId), bob);
    }

    // B6: stranger approve revert
    function test_approve_unauthorized_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(SimpleERC721.NotOwnerNorApproved.selector);
        nft.approve(bob, tokenId);
    }

    // C10 + C11: approved can transfer, approval cleared
    function test_transferFrom_byApproved_succeeds_andClearsApproval() public {
        vm.prank(alice);
        nft.approve(bob, tokenId);

        vm.prank(bob);
        nft.transferFrom(alice, bob, tokenId);

        assertEq(nft.ownerOf(tokenId), bob);
        assertEq(nft.getApproved(tokenId), address(0));
    }
}
```

> 小技巧：
- `vm.expectEmit` 的四个 bool 表示是否校验：topic1/topic2/topic3/data  
- `Approval` 的 indexed 参数一般是 `owner` 与 `approved`（topic），`tokenId` 可能是 data（视你事件定义而定）

---

## 常见坑 & 对应修复

### 1）“我想给 setApprovalForAll 加 NotOwnerNorApproved 校验”
不需要，也不应该。  
`setApprovalForAll` 只允许设置 `msg.sender` 自己的 operator 表，不会影响别人资产。

### 2）转移后忘记清空 `getApproved(tokenId)`
标准行为：**transfer 后应清空 tokenApproval**，否则旧的 approved 可能继续有效造成风险。

### 3）Approval 事件里的 owner 不是 msg.sender
当 `operator` 调用 `approve` 时，事件里的 `owner` 仍然是 token owner（不是 operator）。

---

## 小结
- `setApprovalForAll`：owner 给予 operator “全量操作权”，常见给市场合约  
- `approve`：单 token 授权给某地址  
- 真正需要 `NotOwnerNorApproved` 的地方：`approve/transferFrom/safeTransferFrom` 等“对 tokenId 的操作”

---

## 下一步（D11 可选方向）
- `safeTransferFrom` + `IERC721Receiver` 的回调验证（合约接收方必须返回 magic value）
- fuzz：随机 tokenId / 随机 owner/operator 的授权与转移组合测试
