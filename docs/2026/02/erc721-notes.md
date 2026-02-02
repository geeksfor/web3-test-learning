# ERC-721（NFT）标准复习笔记

tags: [ethereum, erc721, nft, solidity, foundry, testing]

> 目标：用最少的概念把 ERC-721 讲清楚：**是什么、解决什么、用来做什么、核心接口与测试点**。  
> 适用：日常复习、面试速查、写测试前快速过一遍。

---

## 1. ERC-721 是什么？

**ERC-721** 是以太坊生态里最主流的 **NFT（Non-Fungible Token，非同质化代币）标准**。  
它定义了一组统一接口，让“每一个都独一无二”的链上资产可以被钱包、市场、DApp 识别与交互。

一句话：**ERC-721 = 链上唯一资产的“所有权凭证 + 标准化操作接口”。**

---

## 2. 它解决了什么问题？

和 ERC-20（同质化代币）不同，ERC-721 的关键是：

- **唯一性（Non-Fungible）**：每个 token 用 `tokenId` 唯一标识，彼此不可互换（1 号 token ≠ 2 号 token）。
- **可验证所有权**：链上可查询任意 `tokenId` 当前归属（谁是 owner）。
- **统一转移/授权方式**：第三方应用无需单独适配每个项目，自然能转移、授权、展示。

---

## 3. 主要用来做什么？（典型场景）

ERC-721 适合表示“独一无二”的东西：

1. **数字收藏品 / 艺术品 / PFP**：每个作品对应一个 `tokenId`
2. **游戏资产**：角色、装备、稀有道具（唯一性强）
3. **门票 / 会员资格 / 凭证**：活动票、会员卡、资格证明（是否可转让由合约决定）
4. **现实资产映射（RWA）凭证**：证书/仓单/鉴定等（注意：链上 token ≠ 自动具备法律意义，需要线下配套）
5. **域名类资产**：每个域名唯一（本质也是 `tokenId` 唯一）

---

## 4. 核心概念与数据结构

### 4.1 tokenId
- 每个 NFT 的唯一编号（`uint256`）
- NFT 的“身份”就是 tokenId

### 4.2 owner / balance
- `ownerOf(tokenId)`：查询某个 token 的拥有者
- `balanceOf(owner)`：某个地址持有多少个 NFT（数量，不区分 tokenId）

### 4.3 授权（Approval）模型
ERC-721 主要有两种授权：

- **单 token 授权**：`approve(to, tokenId)`
  - 授权 `to` 可以转移某个具体 token
- **全量 operator 授权**：`setApprovalForAll(operator, approved)`
  - 授权 operator 可以操作 owner 名下所有 token（常见于 NFT 市场/托管合约）

---

## 5. 标准接口速查（高频）

> 不同实现可能还有扩展（mint/burn、Enumerable、Royalty 等），但下列是“对接生态”最关键的部分。

### 5.1 查询
- `balanceOf(address owner) -> uint256`
- `ownerOf(uint256 tokenId) -> address`

### 5.2 授权
- `approve(address to, uint256 tokenId)`
- `getApproved(uint256 tokenId) -> address`
- `setApprovalForAll(address operator, bool approved)`
- `isApprovedForAll(address owner, address operator) -> bool`

### 5.3 转移
- `transferFrom(address from, address to, uint256 tokenId)`
- `safeTransferFrom(address from, address to, uint256 tokenId)`
- `safeTransferFrom(address from, address to, uint256 tokenId, bytes data)`

### 5.4 事件（非常重要：市场/钱包靠它刷新状态）
- `Transfer(address indexed from, address indexed to, uint256 indexed tokenId)`
- `Approval(address indexed owner, address indexed approved, uint256 indexed tokenId)`
- `ApprovalForAll(address indexed owner, address indexed operator, bool approved)`

---

## 6. safeTransferFrom 为什么“更安全”？

当接收方是 **合约地址** 时，普通 `transferFrom` 可能把 NFT 转进一个不支持接收的合约里，导致 NFT “卡死”。

`safeTransferFrom` 会要求接收合约实现回调：

- `onERC721Received(...) -> bytes4`

如果接收合约没有正确实现，转移会 **revert**，从而避免 NFT 被误转。

---

## 7. 元数据（Metadata）与 tokenURI

多数 NFT 会实现 ERC-721 Metadata 扩展：

- `name()`
- `symbol()`
- `tokenURI(tokenId)`：返回一个 URI（常见是 `ipfs://...` 或 https），指向 JSON 元数据

JSON 元数据常见字段：
- `name`
- `description`
- `image`
- `attributes`（属性列表）

> 测试/审计时常关注：tokenURI 是否可任意改动？项目是否需要“冻结元数据”？是否存在中心化风险？

---

## 8. ERC-721 vs ERC-1155（常见对比）

- **ERC-721**：每个 token 唯一（1/1），适合收藏品、角色、独特装备
- **ERC-1155**：同一合约可同时表示“可堆叠资产”和“唯一资产”，支持批量转移，更省 gas；游戏类资产常用

---

## 9. 测试与安全检查清单（Foundry 视角）

下面是你写用例时最常覆盖的点：

### 9.1 正常路径
- mint 后：
  - `ownerOf(tokenId)` 正确
  - `balanceOf(owner)` +1
  - `Transfer(address(0), to, tokenId)` 事件正确
- transfer 后：
  - owner 从 A 变为 B
  - balance A -1, balance B +1
  - `Transfer(A, B, tokenId)` 事件正确

### 9.2 异常路径（revert 分支）
- 转移不存在的 tokenId：应 revert
- 非 owner/非 approved/非 operator 发起 transfer：应 revert
- `transferFrom` / `safeTransferFrom` 的 `from` 参数不是当前 owner：应 revert
- `approve` 非 owner 且非 operator：应 revert
- `safeTransferFrom` 转给不支持接收的合约：应 revert

### 9.3 授权模型
- `approve(to, tokenId)`：
  - `getApproved(tokenId)` 更新正确
  - 转移后单 token 授权通常会被清空（检查实现行为）
- `setApprovalForAll(operator, true)`：
  - `isApprovedForAll(owner, operator)` 为 true
  - operator 可转移 owner 的任意 token

### 9.4 回调与重入风险（进阶）
- `safeTransferFrom` 会外部调用接收合约的 `onERC721Received`
  - 若实现里有状态更新/资金操作，需关注重入风险
  - 测试可构造恶意接收合约验证防护

---

## 10. 复习速记（30 秒）

- ERC-721 = NFT 标准：**每个 token 用 tokenId 唯一标识**
- 核心：`ownerOf / balanceOf / approve / setApprovalForAll / transferFrom / safeTransferFrom`
- `safeTransferFrom` 防止把 NFT 转进“不支持接收”的合约而卡死
- 测试重点：所有权变化、事件、授权逻辑、revert 分支、合约接收回调

---

## 11. 下一步建议（按学习路径）

如果你接下来要用 Foundry 深入练：
1. 写一个最小 ERC-721（或直接用 OpenZeppelin ERC721）
2. 覆盖 mint/transfer/approve/operator/safeTransferFrom 的全链路测试
3. 写一个「不实现 onERC721Received 的合约」来测 safeTransfer revert
4. 再写一个「恶意接收合约」练重入/回调理解

---

*文件生成时间：2026-02-03*
