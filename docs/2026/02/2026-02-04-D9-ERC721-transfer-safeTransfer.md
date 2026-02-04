# 2026-02-04 - D9：ERC721 transferFrom / safeTransferFrom（正常 + 未授权 revert）

tags: [foundry, forge, solidity, testing, erc721, transferFrom, safeTransferFrom, approvals]


## 背景 / 目标
在 D8 的最小 ERC721（`mint / ownerOf / balanceOf`）基础上，今天目标把 NFT 的**转移链路**跑通，并用测试锁住权限与安全语义：

1. **transferFrom 正常路径**
   - owner 直接转账成功
   - 单 token 授权（`approve`）后，approved 地址可转账
   - 全局授权（`setApprovalForAll`）后，operator 可转账
   - 状态变化正确：`ownerOf` 更新、双方 `balanceOf` ±1、`Transfer` 事件
   - **关键：转账后 token 授权必须清空**（`getApproved(tokenId) == 0`）

2. **transferFrom 异常路径**
   - 非 owner 且未授权：必须 revert（权限检查）

3. **safeTransferFrom 安全转移**
   - 转给 EOA：成功
   - 转给实现了 `onERC721Received` 的合约：成功
   - 转给未实现 receiver 的合约：必须 revert（防止 NFT 被锁死）

---

## 今日完成清单
- [x] 在合约中加入 approvals：`approve/getApproved/setApprovalForAll/isApprovedForAll`
- [x] 实现 `transferFrom`：owner / approved / operator 权限校验 + 清空 token 授权
- [x] 实现 `safeTransferFrom`：对合约接收者做 `IERC721Receiver` 回调校验
- [x] 单测覆盖：正常转移 + 未授权 revert + safeTransferFrom 的 Good/Bad receiver

---

## 一、合约改动（src/SimpleERC721.sol）
> 目标：实现 D9 所需的最小转账与授权能力。下面代码为“最小可用版本”，不引入 OZ，便于理解。

### 1.1 新增接口：IERC721Receiver
```solidity
interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}
```

### 1.2 新增状态
```solidity
mapping(uint256 => address) private _tokenApprovals;                     // getApproved
mapping(address => mapping(address => bool)) private _operatorApprovals; // isApprovedForAll
```

### 1.3 新增事件（建议加上，测试更完整）
```solidity
event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
```

### 1.4 新增错误（建议）
```solidity
error NotOwnerNorApproved();
error InvalidFrom();
error UnsafeRecipient();
```

### 1.5 approvals 实现
```solidity
function getApproved(uint256 tokenId) public view returns (address) {
    ownerOf(tokenId); // 不存在则 revert
    return _tokenApprovals[tokenId];
}

function isApprovedForAll(address owner, address operator) public view returns (bool) {
    return _operatorApprovals[owner][operator];
}

function approve(address to, uint256 tokenId) external {
    address owner = ownerOf(tokenId);
    if (msg.sender != owner && !_operatorApprovals[owner][msg.sender]) revert NotOwnerNorApproved();
    _tokenApprovals[tokenId] = to;
    emit Approval(owner, to, tokenId);
}

function setApprovalForAll(address operator, bool approved) external {
    _operatorApprovals[msg.sender][operator] = approved;
    emit ApprovalForAll(msg.sender, operator, approved);
}
```

### 1.6 transferFrom 实现（核心）
```solidity
function transferFrom(address from, address to, uint256 tokenId) public {
    if (to == address(0)) revert ZeroAddress();

    address owner = ownerOf(tokenId);
    if (owner != from) revert InvalidFrom();

    bool authorized =
        (msg.sender == owner) ||
        (msg.sender == _tokenApprovals[tokenId]) ||
        (_operatorApprovals[owner][msg.sender]);

    if (!authorized) revert NotOwnerNorApproved();

    // 关键：清空 token 授权（否则会留下权限残留）
    if (_tokenApprovals[tokenId] != address(0)) {
        _tokenApprovals[tokenId] = address(0);
        emit Approval(owner, address(0), tokenId);
    }

    unchecked {
        _balanceOf[from] -= 1;
        _balanceOf[to] += 1;
    }
    _ownerOf[tokenId] = to;

    emit Transfer(from, to, tokenId);
}
```

### 1.7 safeTransferFrom 实现（安全转移）
```solidity
function safeTransferFrom(address from, address to, uint256 tokenId) external {
    safeTransferFrom(from, to, tokenId, "");
}

function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
    transferFrom(from, to, tokenId);

    // to 是合约：必须实现 ERC721Receiver
    if (to.code.length > 0) {
        bytes4 ret = IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data);
        if (ret != IERC721Receiver.onERC721Received.selector) revert UnsafeRecipient();
    }
}
```

---

## 二、测试设计（test/SimpleERC721.D9.t.sol）
### 2.1 测试角色与准备
- `alice`：初始 owner（mint 给她）
- `bob`：接收者
- `eve`：未授权攻击者（应 revert）
- `op`：operator（ApprovalForAll）

`setUp()`：
```solidity
nft = new SimpleERC721();
nft.mint(alice, 1);
```

---

## 三、完整测试代码（可直接复制）
> 覆盖点：transferFrom 正常 + 未授权 revert；safeTransferFrom EOA/GoodReceiver/BadReceiver。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleERC721.sol";

contract GoodReceiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract BadReceiver {
    // 不实现 onERC721Received
}

contract SimpleERC721D9Test is Test {
    SimpleERC721 nft;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address eve   = address(0xEVE);
    address op    = address(0x0P);

    function setUp() public {
        nft = new SimpleERC721();
        nft.mint(alice, 1);
    }

    // -------- transferFrom：owner 直接转 --------
    function test_transferFrom_success_byOwner() public {
        vm.expectEmit(true, true, true, false);
        emit SimpleERC721.Transfer(alice, bob, 1);

        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);

        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 1);
        assertEq(nft.getApproved(1), address(0));
    }

    // -------- transferFrom：非 owner 且未授权 -> revert --------
    function test_transferFrom_reverts_ifNotOwnerNorApproved() public {
        vm.expectRevert(SimpleERC721.NotOwnerNorApproved.selector);
        vm.prank(eve);
        nft.transferFrom(alice, bob, 1);
    }

    // -------- transferFrom：approve 后由 approved 地址转 --------
    function test_transferFrom_success_byApproved() public {
        vm.prank(alice);
        nft.approve(eve, 1);
        assertEq(nft.getApproved(1), eve);

        vm.prank(eve);
        nft.transferFrom(alice, bob, 1);

        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 1);
        // 关键：授权清空
        assertEq(nft.getApproved(1), address(0));
    }

    // -------- transferFrom：ApprovalForAll 后由 operator 转 --------
    function test_transferFrom_success_byOperator() public {
        vm.prank(alice);
        nft.setApprovalForAll(op, true);
        assertTrue(nft.isApprovedForAll(alice, op));

        vm.prank(op);
        nft.transferFrom(alice, bob, 1);

        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 1);
        assertEq(nft.getApproved(1), address(0));
    }

    // -------- safeTransferFrom：to 是 EOA -> 成功 --------
    function test_safeTransferFrom_success_toEOA() public {
        vm.prank(alice);
        nft.safeTransferFrom(alice, bob, 1);

        assertEq(nft.ownerOf(1), bob);
    }

    // -------- safeTransferFrom：to 是 GoodReceiver 合约 -> 成功 --------
    function test_safeTransferFrom_success_toGoodReceiver() public {
        GoodReceiver r = new GoodReceiver();

        vm.prank(alice);
        nft.safeTransferFrom(alice, address(r), 1);

        assertEq(nft.ownerOf(1), address(r));
    }

    // -------- safeTransferFrom：to 是 BadReceiver 合约 -> revert --------
    function test_safeTransferFrom_reverts_toBadReceiver() public {
        BadReceiver r = new BadReceiver();

        vm.expectRevert(SimpleERC721.UnsafeRecipient.selector);
        vm.prank(alice);
        nft.safeTransferFrom(alice, address(r), 1);
    }
}
```

---

## 四、运行命令
### 4.1 跑 D9 文件
```bash
forge test --match-path test/SimpleERC721.D9.t.sol -vvv
```

### 4.2 只跑某个用例
```bash
forge test --match-test test_transferFrom_success_byApproved -vvv
forge test --match-test test_safeTransferFrom_reverts_toBadReceiver -vvv
```

---

## 五、关键知识点总结
### 5.1 ERC721 权限判定（transferFrom 的“谁能转”）
任意转账都必须满足：
- `msg.sender == owner` **或**
- `msg.sender == getApproved(tokenId)`（单 token 授权）**或**
- `isApprovedForAll(owner, msg.sender)`（全局授权）

否则必须 revert。

### 5.2 为什么转账后要清空 token 授权？
如果不清空：
- `approve(eve, tokenId)` 后转给 bob，eve 仍可能保留对该 token 的操作权限（权限残留）
- 标准实现（如 OZ）会在转账/销毁时清除 token approval

### 5.3 safeTransferFrom 的“安全”在哪里？
当 `to` 是合约地址：
- 必须能成功调用 `onERC721Received`
- 并且返回值必须等于 `IERC721Receiver.onERC721Received.selector`
否则 revert，避免 NFT 发送到不会处理 ERC721 的合约里导致资产锁死。

---

## 六、分支命名建议
推荐：`d9-erc721-transfer-safeTransfer-auth`

---

## 七、下一步（D10 建议）
- 扩展 revert 分支：`from` 不匹配、`to=0`、token 不存在、approve 权限限制等
- 让 `GoodReceiver` 记录参数，并断言 operator/from/tokenId/data（更严谨）
- 引入 invariant（状态机）：随机 mint/approve/transferFrom，多角色交互，写更强不变量：
  - `balanceOf(owner) == ownedCount(owner)`
  - 已存在 token 的 `ownerOf(tokenId) != 0`
