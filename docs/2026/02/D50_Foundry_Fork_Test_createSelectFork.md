# D50：Foundry Fork 测试入门（createSelectFork + 固定区块）

> 目标：学会用 Foundry 在 **主网 fork** 上跑测试：`createSelectFork`、**固定 block**、跑通一次 fork，并理解“区块/交易/状态”之间的关系。  
> 适用场景：复现线上事件、写审计 PoC、对真实协议做集成测试（不靠 mock）。

---

## 你将学到什么

1. **Fork 测试是什么**：把某条链（如 Ethereum Mainnet）在某个历史区块的“全局状态快照”复制到本地 EVM。
2. **为什么要固定区块**：避免“最新状态变化”导致测试不稳定，确保可复现。
3. **createSelectFork 的作用**：创建 fork 并切换到该 fork，在固定区块上执行后续测试。
4. **如何选择 USDC 和 whale 地址**：USDC 是主网固定合约地址；whale 是在你固定区块上余额足够大的地址（需要验证/筛选）。
5. **理解区块与地址的关系**：区块存交易与 stateRoot（状态指纹），地址/余额属于“全局状态”，不是“装在某个区块里”。

---

## 知识点与原理（通俗易懂）

### 1) Fork 测试是什么？
- 你本地跑的是一个 EVM（forge test）。
- 但它会通过 RPC（如 Infura/Alchemy）从主网拉取某个区块的状态（合约代码、存储、余额等），复制成一份本地快照。
- **读数据**：读到真实链上该区块的状态；  
  **写操作**：只写到你本地的 fork 世界，不会影响真实主网。

### 2) 为什么要固定 block？
- 如果每次都 fork “最新区块”，链上状态会变化（余额、池子储备、价格、利率等），测试会“时灵时不灵”。
- 固定区块号 = **可复现**（同一 block 下状态一致，断言稳定）。

### 3) createSelectFork 做了什么？
`vm.createSelectFork(rpcUrl, blockNumber)`：
- 用 `rpcUrl` 拉取 `blockNumber` 的链上状态
- 并**立即切换**当前测试运行环境到这个 fork（select）

### 4) RPC（ETH_RPC_URL）是什么？跟 USDC/whale 什么关系？
- RPC 是你访问链上数据的“入口/管道”（节点服务）。
- USDC 是链上的一个合约地址，whale 是链上的一个地址。
- 你在测试里调用 `USDC.balanceOf(whale)` 时，Foundry 会通过 RPC 去读取你固定区块时刻的状态并返回结果。  
**一句话：RPC 决定你 fork 的链/区块；USDC/whale 是那份链上状态里的对象。**

---

## 操作步骤（从 0 到跑通一次 fork）

### Step 0：准备 ETH_RPC_URL（主网 RPC）
你需要一个 Ethereum Mainnet RPC（Infura/Alchemy/QuickNode/自建节点都可）。

#### 验证 RPC 是否可用
```bash
curl --url https://mainnet.infura.io/v3/<YOUR_PROJECT_ID> \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```
如果返回形如：
```json
{"jsonrpc":"2.0","id":1,"result":"0x..."}
```
表示 RPC 正常可用（result 是十六进制区块号）。

> 安全提醒：不要把带 key 的 RPC 地址提交到 GitHub，建议放环境变量或 `.env`（并加入 `.gitignore`）。

#### 设置环境变量（推荐）
```bash
export ETH_RPC_URL="https://mainnet.infura.io/v3/<YOUR_PROJECT_ID>"
```

---

### Step 1：可选配置 foundry.toml
```toml
[rpc_endpoints]
mainnet = "${ETH_RPC_URL}"
```

---

### Step 2：写最小 Fork 测试（USDC + whale 转账）

新建文件：`test/D50_Fork.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract D50_Fork_Test is Test {
    // Ethereum mainnet USDC (Circle)
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // 固定区块号（示例，可替换为你想复现的事件区块）
    uint256 constant FORK_BLOCK = 17_000_000;

    // 在该区块“可能”持有大量 USDC 的地址（需要用 balanceOf 验证）
    address constant USDC_WHALE = 0x55FE002aefF02F77364de339a1292923A15844B8;

    address alice = makeAddr("alice");

    function setUp() public {
        string memory rpc = vm.envString("ETH_RPC_URL");
        vm.createSelectFork(rpc, FORK_BLOCK);

        // 保险：确认 USDC 在该链上确实有代码（防止 RPC 指到错误网络）
        assertGt(USDC.code.length, 0, "USDC has no code on this chain");
    }

    function test_fork_readAndTransferUSDC() public {
        IERC20 usdc = IERC20(USDC);

        uint256 whaleBal = usdc.balanceOf(USDC_WHALE);
        emit log_named_uint("whale USDC balance", whaleBal);

        // 断言：这个地址在该区块确实有钱（否则换地址/换区块）
        assertGt(whaleBal, 1_000_000e6, "whale balance too small at this block");

        // Fork 环境可以“扮演”任何地址发起调用（用于测试/审计 PoC）
        vm.prank(USDC_WHALE);
        bool ok = usdc.transfer(alice, 100e6); // 100 USDC（USDC decimals=6）
        assertTrue(ok, "transfer failed");

        assertEq(usdc.balanceOf(alice), 100e6, "alice should receive 100 USDC");
        assertEq(usdc.balanceOf(USDC_WHALE), whaleBal - 100e6, "whale balance should decrease");
    }

    function test_fork_blockIsPinned() public view {
        assertEq(block.number, FORK_BLOCK, "block number should be pinned");
    }
}
```

运行：
```bash
forge test --match-contract D50_Fork_Test -vvv
```

---

## USDC 与 USDC_WHALE 如何确定？

### 1) USDC 合约地址怎么确定？
USDC 主网合约地址是固定的（常用、公开可核对）：
- `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`

你也可以在 Etherscan / Circle 官方渠道核对后写死。

### 2) whale 地址怎么确定？
whale 不是“拍脑袋”，关键是：**在你固定的 FORK_BLOCK 上余额必须足够**。

最常用流程：
1. 去区块浏览器（如 Etherscan）USDC 页面 → holders（持有人）  
2. 复制若干“候选大户地址”
3. 在测试里用 `balanceOf` **验证**该区块余额是否足够，不够就换地址或换区块。

---

## 进阶：自动筛选“在该区块可用”的 whale（更稳）

如果你不想手动猜 whale，建议写一个候选列表自动挑一个余额过阈值的地址：

```solidity
address whale;

function setUp() public {
    vm.createSelectFork(vm.envString("ETH_RPC_URL"), FORK_BLOCK);

    address[] memory candidates = new address[](5);
    candidates[0] = 0x55FE002aefF02F77364de339a1292923A15844B8;
    candidates[1] = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;
    candidates[2] = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
    candidates[3] = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    candidates[4] = 0x0000000000000000000000000000000000000000;

    IERC20 usdc = IERC20(USDC);
    uint256 threshold = 1_000_000e6;

    for (uint256 i = 0; i < candidates.length; i++) {
        if (candidates[i] == address(0)) continue;
        uint256 bal = usdc.balanceOf(candidates[i]);
        if (bal > threshold) {
            whale = candidates[i];
            break;
        }
    }

    require(whale != address(0), "no whale found; add more candidates or change block");
}
```

> 注意：示例候选地址仅作演示。你应从 Etherscan holders 或你要复现的协议地址（比如某金库/池子/treasury）补充候选。

---

## FAQ：把我们对话中的问题与答案整理在这里

### Q1：ETH_RPC_URL 从哪里获取？
从节点服务商申请（Infura/Alchemy/QuickNode 等）：
- Infura：`https://mainnet.infura.io/v3/<PROJECT_ID>`
- Alchemy：`https://eth-mainnet.g.alchemy.com/v2/<API_KEY>`

### Q2：我这个 Infura URL 是正确的主网 RPC 吗？
用 `eth_blockNumber` 测试返回 `result`（十六进制区块号）即可证明可用且是主网。你已经成功返回了区块号。

### Q3：USDC 和 whale 跟 RPC 有什么关系？
RPC 是“入口”，用来在 fork 时拉取某区块的链上状态；USDC/whale 是那份状态里的对象。  
你调用 `balanceOf` 时，Foundry 通过 RPC 从该区块状态里读余额。

### Q4：FORK_BLOCK 和 USDC_WHALE 必须是“同一个区块”吗？
更准确说：你 fork 到 `FORK_BLOCK` 后，读到的是“该区块状态快照”。  
whale 地址在这个快照中必须有足够余额；否则你的转账断言会失败 → 换 whale 或换区块。

### Q5：区块里有交易记录，那 whale 地址一定“在这个区块里”吗？
不是。**区块不是装地址的盒子**。  
- 区块里主要有：交易列表 + 状态指纹（stateRoot）
- 地址/余额属于“全局状态账本”，不是存放在区块交易列表里  
你查询余额是在问：“在区块 N 的状态快照里，这个地址余额是多少”。

**类比**：  
- 全局状态 = 银行总账数据库  
- 区块交易 = 当天流水  
- stateRoot = 当天结账后的总账指纹  
- whale = 银行大客户  
你关心的是“那天结账时他账户余额”，而不是“当天流水里是否出现过他的名字”。

---

## 常见坑与排查

1. **RPC 指到错误网络**：`USDC.code.length == 0`，立刻发现。
2. **whale 在该区块余额不足**：`balanceOf` 断言失败，换候选/换区块。
3. **decimals 搞错**：USDC 是 6 位，`100e6` 才是 100 USDC。
4. **RPC 限流/超时**：换更稳定的服务商或提高套餐/额度。

---

## 审计/实战视角：为什么 fork 测试很重要？
- 复现真实线上事件（例如 AMM 价格操纵、夹子、闪电贷）
- 写“攻击前后资产变化”的断言（审计 PoC 的核心）
- 对真实协议做集成回归测试（避免 mock 与现实偏差）

---

## 建议的分支与提交信息（可选）

- Branch: `d50-fork-createSelectFork`
- Commit:
  - `test(d50): add mainnet fork test with pinned block (createSelectFork)`
  - `docs(d50): add D50 fork testing notes and faq`

