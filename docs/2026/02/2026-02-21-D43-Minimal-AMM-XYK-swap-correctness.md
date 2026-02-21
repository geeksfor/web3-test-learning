# D43｜最小 AMM（x*y=k）+ Swap 基本正确性（含审计视角）

日期：2026-02-21  
主题：搭一个最小 AMM（x*y=k），写 swap 基本正确性测试；理解滑点、minOut；理解储备类型 uint112 与取整导致的 k 变化。

---

## 1. 这节在解决什么问题（通俗解释）

把 AMM 想成一个“自动报价兑换机”。池子里有两种币（Token0、Token1）：

- 储备（库存）：`x = reserve0`、`y = reserve1`
- 规则：尽量满足 `x * y = k`（常量乘积）
- 当你拿 `amountIn` 个 Token0 来换 Token1：
  - Token0 进入池子：`x' = x + amountIn`（有手续费时是 `x' = x + amountInAfterFee`）
  - 为了维持乘积关系：`y' = k / x'`
  - 你能拿到 Token1：`amountOut = y - y'`

**直觉：** 你买得越多，越“推走价格”，拿到的越少，这就是 **滑点**。

---

## 2. 通过 D43 你能学到什么

1) **AMM 定价的本质**：不是挂单撮合，而是按储备 + 公式即时定价。  
2) **滑点从哪来**：你改变了池子储备比例，越大额越滑。  
3) **swap 正确性测试怎么写**（Foundry）：
   - 输出是否匹配公式（同一套公式算 expectedOut）
   - swap 后储备是否与合约余额一致（reserve == balance）
   - `minOut`（滑点保护）是否生效（不满足则 revert）
4) **审计视角**：最常见风险点：储备/余额不一致、缺少 minOut、fee 处理错误、重入与恶意 token、取整误差导致断言写错。

---

## 3. 最小实现设计（本次示例）

### 3.1 合约
- `SimpleAMMXYK`：
  - `seed(amount0, amount1)`：最小“加流动性”（直接转入 + sync），不实现 LP token
  - `swap0For1(amountIn, minOut, to)`：用 token0 换 token1
  - `swap1For0(...)`：对称逻辑
  - `feeBps`：可选手续费（bps=1/10000），本次先用 0 更直观

### 3.2 测试
- `test_swap0For1_basicCorrectness_matchesFormula`
- `test_swap0For1_slippageProtection_revertsWhenMinOutTooHigh`
- （可选）关于 `k` 的取整边界测试（注意：不要用 `+1` 这种过小容差）

---

## 4. 关键代码（合约 + 测试）

> 代码路径建议：
- `labs/foundry-labs/src/amm/SimpleAMMXYK.sol`
- `labs/foundry-labs/src/tokens/SimpleERC20.sol`
- `labs/foundry-labs/test/amm/D43_SimpleAMMXYK.t.sol`

### 4.1 最小 ERC20（可 mint）
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SimpleERC20 {
    string public name;
    string public symbol;
    uint8  public immutable decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory n, string memory s) {
        name = n;
        symbol = s;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
```

### 4.2 最小 AMM（x*y=k + minOut + 可选 fee）
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

contract SimpleAMMXYK {
    IERC20Like public immutable token0;
    IERC20Like public immutable token1;

    // 经典做法：用 uint112 便于 storage packing（见 Q&A）
    uint112 public reserve0;
    uint112 public reserve1;

    uint16 public immutable feeBps; // 0 or 30 (0.3%)

    error ZeroAmount();
    error InsufficientLiquidity();
    error SlippageTooHigh(uint256 out, uint256 minOut);

    event Sync(uint112 r0, uint112 r1);
    event Swap(address indexed sender, address indexed tokenIn, uint256 amountIn, uint256 amountOut, address indexed to);

    constructor(address _token0, address _token1, uint16 _feeBps) {
        token0 = IERC20Like(_token0);
        token1 = IERC20Like(_token1);
        feeBps = _feeBps;
    }

    function _syncFromBalances() internal {
        uint256 b0 = token0.balanceOf(address(this));
        uint256 b1 = token1.balanceOf(address(this));

        // 审计点：真实项目建议加上限检查，防止强转截断
        // require(b0 <= type(uint112).max && b1 <= type(uint112).max, "overflow");

        reserve0 = uint112(b0);
        reserve1 = uint112(b1);
        emit Sync(reserve0, reserve1);
    }

    function seed(uint256 amount0, uint256 amount1) external {
        if (amount0 == 0 || amount1 == 0) revert ZeroAmount();
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
        _syncFromBalances();
    }

    function swap0For1(uint256 amountIn, uint256 minOut, address to) external returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();

        token0.transferFrom(msg.sender, address(this), amountIn);

        uint256 amountInAfterFee = amountIn * (10_000 - feeBps) / 10_000;

        uint256 x = uint256(reserve0);
        uint256 y = uint256(reserve1);
        uint256 k = x * y;

        uint256 xNew = x + amountInAfterFee;
        uint256 yNew = k / xNew; // floor division
        amountOut = y - yNew;

        if (amountOut == 0) revert InsufficientLiquidity();
        if (amountOut < minOut) revert SlippageTooHigh(amountOut, minOut);

        token1.transfer(to, amountOut);
        _syncFromBalances();

        emit Swap(msg.sender, address(token0), amountIn, amountOut, to);
    }
}
```

### 4.3 Foundry 测试（swap 正确性 + minOut 保护）
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/tokens/SimpleERC20.sol";
import "../../src/amm/SimpleAMMXYK.sol";

contract D43_SimpleAMMXYK_Test is Test {
    SimpleERC20 t0;
    SimpleERC20 t1;
    SimpleAMMXYK amm;

    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");

    function setUp() public {
        t0 = new SimpleERC20("Token0", "T0");
        t1 = new SimpleERC20("Token1", "T1");
        amm = new SimpleAMMXYK(address(t0), address(t1), 0); // no-fee

        t0.mint(alice, 10_000 ether);
        t1.mint(alice, 10_000 ether);

        vm.startPrank(alice);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        amm.seed(1_000 ether, 1_000 ether);
        vm.stopPrank();
    }

    function test_swap0For1_basicCorrectness_matchesFormula() public {
        t0.mint(bob, 10 ether);

        uint256 x = uint256(amm.reserve0());
        uint256 y = uint256(amm.reserve1());
        uint256 k = x * y;

        uint256 amountIn = 1 ether;
        uint256 expectedOut = y - (k / (x + amountIn)); // fee=0

        uint256 bob1Before = t1.balanceOf(bob);

        vm.startPrank(bob);
        t0.approve(address(amm), amountIn);
        uint256 out = amm.swap0For1(amountIn, 0, bob);
        vm.stopPrank();

        assertEq(out, expectedOut, "amountOut matches x*y=k formula");
        assertEq(t1.balanceOf(bob) - bob1Before, expectedOut, "bob receives correct token1");

        assertEq(uint256(amm.reserve0()), t0.balanceOf(address(amm)), "reserve0 == balance0");
        assertEq(uint256(amm.reserve1()), t1.balanceOf(address(amm)), "reserve1 == balance1");
    }

    function test_swap0For1_slippageProtection_revertsWhenMinOutTooHigh() public {
        t0.mint(bob, 10 ether);

        uint256 amountIn = 1 ether;
        uint256 impossibleMinOut = 10_000 ether;

        vm.startPrank(bob);
        t0.approve(address(amm), amountIn);
        vm.expectRevert(SimpleAMMXYK.SlippageTooHigh.selector);
        amm.swap0For1(amountIn, impossibleMinOut, bob);
        vm.stopPrank();
    }
}
```

---

## 5. Q&A：今天遇到的关键问题与答案（已整理入文档）

### Q1：为什么储备要用 `uint112`？为什么要转 `uint112`？
**原因：省 gas + storage packing。**  
EVM 一个 storage slot 是 32 bytes。`uint112(14 bytes) + uint112(14 bytes) + uint32(4 bytes)` 刚好 32 bytes，能把多个变量塞进同一个 slot，减少 SLOAD/SSTORE。  

**范围是否够用？** `uint112` 最大约 `5.19e33`，即使 18 位小数，也能表示约 `5.19e15` 的“人类单位”，通常远超真实池子规模。

**审计风险：强转截断**  
如果 `balance > type(uint112).max`，强转会截断导致储备错误。真实项目建议加：
```solidity
require(b0 <= type(uint112).max && b1 <= type(uint112).max, "overflow");
```

---

### Q2：为什么测试里 “k should not drop materially” 会失败？
你看到的 trace（示例）：
- swap 后 `reserve0 = 1.01e21`，`reserve1 = 9.90099e20`
- 断言 `kAfter + 1 >= kBefore` 失败

**根因：整数除法向下取整（floor）会让 k 减少的不止 1。**  
无手续费时：`yNew = floor(k / xNew)`  
所以：`kAfter = xNew * yNew = xNew * floor(k/xNew) <= kBefore`

并且差值：
- `kBefore - kAfter = kBefore % xNew`
- 余数范围 `[0, xNew-1]` → **k 最多可能减少接近 xNew 的量级**，不是 1 wei。

**正确写法（可选）**：与其 `+1`，更合理的边界断言：
```solidity
assertTrue(kAfter <= kBefore, "k should not increase without fee");
assertTrue(kBefore - kAfter < xNew, "k drop bounded by xNew (rounding bound)");
```

> 实践建议：D43 最小实现优先测 **amountOut 是否匹配公式** + **reserve==balance**，更稳、更贴合“正确性”。

---

### Q3：为什么需要滑点保护 `minOut`？
**因为从你发交易到上链执行之间，价格可能变化**（mempool 窗口）。  
没有 `minOut` 等价于：**“无论最终成交价多差我都接受”**，会出现：

- **被夹子/MEV（sandwich）**：前置推价让你更亏、后置回拉套利，损失来自你的滑点
- **自然波动**：别人也在交易池子，导致你执行时输出变少
- **自己大额交易**：交易额越大滑点越大，没有下限保护容易“超预期亏损”

`minOut` 的作用：若实际 `amountOut < minOut`，交易直接 revert，不成交，保护用户。

---

## 6. 审计视角 Checklist（D43 对应）

- [ ] **minOut / deadline**：swap 是否具备滑点与过期保护（至少 minOut）
- [ ] **reserve 与余额一致性**：swap 后 reserve 是否 sync 到真实余额（避免 “记账储备” 与真实余额漂移）
- [ ] **fee 处理正确**：fee 是从 amountIn 扣还是从 amountOut 扣？实现是否一致？
- [ ] **重入风险**：swap 中有外部调用（token transfer/transferFrom），是否需要 ReentrancyGuard（遇恶意 token）
- [ ] **取整与边界**：公式的 floor/rounding 是否会导致预期偏差？测试断言是否合理？
- [ ] **溢出/强转**：uint112 强转是否做上限检查（防截断）

---

## 7. 运行方式

```bash
cd labs/foundry-labs
forge test --match-contract D43_SimpleAMMXYK_Test -vvv
```

---

## 8. 分支与提交建议

- 分支：`d43-amm-xyk-swap`
- 提交信息（建议）：
  - `feat(d43): add minimal xyk AMM with minOut and swap correctness tests`
