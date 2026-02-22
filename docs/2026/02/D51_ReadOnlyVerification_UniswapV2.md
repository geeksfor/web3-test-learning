# D51：只读验证（Read-only Verification）实践：以 Uniswap V2 Pair 为例

> 目标：**不做复杂交互**（不 swap、不加/减流动性），只用 `view/staticcall` 读取关键状态，并对“应该一直成立”的规则做断言（不变量）。  
> 这非常贴近审计/监控：把“经验/Checklist”落地成可执行的自动化检查。

---

## 1. 本任务能学到什么

1) **什么是只读验证**：只读链上状态 + 断言不变量（Invariant）  
2) **Foundry mainnet fork** 的核心用法：`createSelectFork`、固定区块保证可复现  
3) **如何定位协议关键合约地址**（以 V2 Pair 为例：Factory.getPair）  
4) **如何写最小 interface** 去读主网合约（无需源码/无需部署）  
5) 审计视角：哪些“异常状态”值得做 read-only 断言（健康检查规则）

---

## 2. 知识点与原理（通俗易懂）

### 2.1 什么是“只读验证”
- 不发交易、不改变合约状态；只做 `view/staticcall` 读取
- 把协议“应该永远成立的规则”写成断言：`assertTrue / assertEq`
- 常用于：审计核对、线上监控规则、CI 定期体检

### 2.2 不变量（Invariant）是什么
不变量就是：**无论发生多少次正常操作，这个条件都应该始终为真**。  
例如 Uniswap V2 Pair 常见只读检查点：
- `token0/token1` 非 0 且不同
- `getReserves()` 的储备 `reserve0/reserve1` 非 0（成熟池）
- `totalSupply > 0`
- `balance(token) >= reserve`（允许 donation：余额可能大于储备，但不应小于）
- `reserve0 * reserve1 > 0`（常量乘积核心量）
- `MINIMUM_LIQUIDITY` 被锁到 `address(0)`（强特征）

---

## 3. 详细步骤（可直接落地到仓库）

> 示例池子：Uniswap V2 **USDC/WETH** Pair（主网）  
> Pair 地址：`0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc`

### Step 0：准备 RPC
```bash
export ETH_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/xxxxx"
```

### Step 1：新增只读接口（interface）

**`src/interfaces/IUniswapV2Pair.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);

    function kLast() external view returns (uint256);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
}
```

**`src/interfaces/IERC20View.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20View {
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}
```

> 建议：interface **按需最小化**，只写你需要调用的函数。对 fork/fork 协议兼容性更好。

### Step 2：写只读验证测试（不变量断言）

**`test/readonly/D51_UniswapV2_Readonly.t.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IUniswapV2Pair} from "src/interfaces/IUniswapV2Pair.sol";
import {IERC20View} from "src/interfaces/IERC20View.sol";

contract D51_UniswapV2_Readonly_Test is Test {
    address constant PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    function setUp() public {
        // 1) fork 到 latest（每次跑结果可能变化）
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        // 2) 如果你要“可复现”，用固定区块：
        // string memory rpc = vm.envString("ETH_RPC_URL");
        // uint256 FORK_BLOCK = 19_000_000;
        // vm.createSelectFork(rpc, FORK_BLOCK);
    }

    // ✅ 纯只读断言：可以标 view（也可以不标）
    function test_readonly_invariants_uniswapV2Pair() public view {
        IUniswapV2Pair pair = IUniswapV2Pair(PAIR);

        // --- 基础地址不变量 ---
        address token0 = pair.token0();
        address token1 = pair.token1();
        assertTrue(token0 != address(0), "token0 is zero");
        assertTrue(token1 != address(0), "token1 is zero");
        assertTrue(token0 != token1, "token0 == token1");

        // --- reserves 不变量 ---
        (uint112 r0, uint112 r1, uint32 tsLast) = pair.getReserves();
        assertTrue(r0 > 0 && r1 > 0, "empty reserves");
        assertTrue(tsLast > 0, "timestampLast should exist");

        // --- 常量乘积核心量 ---
        uint256 k = uint256(r0) * uint256(r1);
        assertTrue(k > 0, "k must be > 0");

        // --- totalSupply 不变量 ---
        uint256 supply = pair.totalSupply();
        assertTrue(supply > 0, "LP totalSupply is zero");

        // --- MINIMUM_LIQUIDITY 锁定（强特征） ---
        uint256 burned = pair.balanceOf(address(0));
        assertTrue(burned >= 1000, "minimum liquidity not locked");

        // --- reserves vs 实际 ERC20 余额（健康检查） ---
        uint256 bal0 = IERC20View(token0).balanceOf(PAIR);
        uint256 bal1 = IERC20View(token1).balanceOf(PAIR);
        assertTrue(bal0 >= uint256(r0), "token0 balance < reserve0");
        assertTrue(bal1 >= uint256(r1), "token1 balance < reserve1");

        // 观测字段：不做强断言也可读
        pair.price0CumulativeLast();
        pair.price1CumulativeLast();
        pair.kLast();
    }

    // ✅ 用于打印信息：包含 emit，因此不要写 view
    function test_readonly_print_basic_info() public {
        IUniswapV2Pair pair = IUniswapV2Pair(PAIR);
        address token0 = pair.token0();
        address token1 = pair.token1();
        (uint112 r0, uint112 r1,) = pair.getReserves();

        emit log_named_address("PAIR", PAIR);
        emit log_named_address("token0", token0);
        emit log_named_address("token1", token1);
        emit log_named_uint("reserve0", r0);
        emit log_named_uint("reserve1", r1);

        emit log_named_string("symbol0", IERC20View(token0).symbol());
        emit log_named_string("symbol1", IERC20View(token1).symbol());
        emit log_named_uint("decimals0", IERC20View(token0).decimals());
        emit log_named_uint("decimals1", IERC20View(token1).decimals());
    }
}
```

### Step 3：运行
```bash
forge test --match-contract D51_UniswapV2_Readonly_Test -vvv
```

---

## 4. 审计视角 Checklist（建议变成断言）

1) **关键地址**
- token0/token1 是否为 0 地址
- token0 是否等于 token1（异常）

2) **核心状态合理性**
- reserves 是否为 0（池子被抽干/未初始化）
- totalSupply 是否为 0（LP 不存在/异常）

3) **账面 vs 真实余额一致性**
- `balance(token, pair) >= reserve`（允许 donation：余额可能更大）
- 反过来 `balance < reserve` 多半提示异常/不同步状态

4) **协议强特征**
- `MINIMUM_LIQUIDITY` 是否锁到 `address(0)`（经典检查点）

---

## 5. 今日问答汇总（把你上面的提问都收进来）

### Q1：直接 transfer 进 Pair，为什么 reserve 不更新？为什么会出现 `balance > reserve`？
**原因：**  
`reserve0/reserve1` 是 Pair 合约自己存的“账本快照”，只会在 `mint/burn/swap/sync` 等路径里调用 `_update()` 才更新。  
如果你只是执行 `token.transfer(pair, amount)`：
- 余额变化发生在 ERC20 合约里：`balanceOf(pair)` 变大
- Pair 合约没被调用 → 没机会更新 `reserve`
因此会出现：
- `token.balanceOf(pair)`（真实余额）**变大**
- `pair.getReserves()`（账面储备）**不变**
=> `balance > reserve`（常见且允许，称为 donation）

反过来 `balance < reserve` 通常不应发生（更像异常/不同步）。

---

### Q2：为什么 `emit log_named_address(...)` 会导致 `view` 报错？
因为 Solidity 认为 `emit`（写日志）属于有副作用的操作，不允许出现在 `view` 函数中。  
所以：
- **纯断言**的测试函数可以写 `view`
- **带 emit 打印**的测试函数不要写 `view`

---

### Q3：`address constant PAIR` 这个地址怎么确定？在哪里找？
最权威可复现方法：从 **Factory.getPair(tokenA, tokenB)** 查出来。  
示例（主网 UniswapV2Factory）：
```solidity
interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}
```
你只要拿到 Factory 地址 + token 地址，就能链上读出 Pair。  
除此之外也可以从 Uniswap App / Etherscan / DEX 页面直接看到 Pair 合约地址，但**写进测试里建议保留 getPair 的可复现来源**。

---

### Q4：`IUniswapV2Pair` 接口里的函数都是“标准必须实现”的吗？
- 对 **Uniswap V2 Pair 的官方实现**：这些函数/字段确实存在（事实标准）。  
- 但它不是 EIP 那种全行业强制标准。其他 DEX/AMM 不一定兼容（例如 Uniswap V3 完全不同）。  
建议：**按需最小化 interface**，只写你要读的函数，兼容性更好。

---

### Q5：`vm.createSelectFork(vm.envString("ETH_RPC_URL"))` vs `vm.createSelectFork(rpc, FORK_BLOCK)` 有啥区别？
- `createSelectFork(envString)`：fork 到 **latest**（当前最新块）→ 状态随时间变化，不一定可复现
- `createSelectFork(rpc, block)`：fork 到 **固定区块** → **强可复现**（CI/审计最推荐）

> 经验：要把 read-only 检查长期放 CI，建议固定区块高度。

---

### Q6：fork 是不是把当时“全局信息”也 fork 下来了？
是的，fork 会把你的本地 EVM “锚定”在某个区块高度的 **世界状态快照（world state）**：
- 账户余额/nonce
- 合约代码（bytecode）
- 合约 storage
- 区块上下文（block.number/timestamp/basefee 等）

但它不是把整条链完整下载下来，而是**按需远程读取 + 本地缓存**：你访问到哪里才去 RPC 拉取对应状态。  
fork 后你在本地执行交易会改变的是**本地副本状态**，不会影响真实链。

---

## 6. 建议分支与提交信息

- 分支：`d51-readonly-uniswapv2-invariants`
- commit：`test(d51): add read-only invariant checks for UniswapV2 pair (mainnet fork)`
