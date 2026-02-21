# D45｜价格操纵（小池子/低流动性）与 TWAP 修复（Foundry）

> 目标：理解 **AMM 小池子为何易被操纵**、spot price 为什么不能当安全预言机；并用 Foundry 写出  
> 1) **攻击前后价格断言**（spot 被明显推歪）  
> 2) **攻击前后借款上限断言**（vuln 版本借款上限被抬高）  
> 3) **TWAP 修复**（同区块/短时间推价骗不过）与对应回归测试

---

## 1. 背景与核心概念（通俗版）

### 1.1 为什么小池子容易被操纵？
在最小的 x*y=k AMM 中，价格近似由储备比值决定：

- `price(token0 in token1) ≈ reserve1 / reserve0`

当池子很小（流动性低），你一笔 swap 就能显著改变 `reserve0/reserve1`，从而造成**巨大价格冲击（price impact）**。  
这就给“依赖 spot price 的协议”留下了被操纵空间。

### 1.2 “价格操纵”攻击的典型链路
1) 协议用 AMM 的 **spot price（瞬时价）** 做估值（例如抵押借贷、清算、mint/burn 定价）  
2) 攻击者先在 AMM **推歪价格**（用大额 swap 改变储备比值）  
3) 同一笔交易/同一区块内，攻击者去调用依赖 spot 的模块 **按歪价获利**

---

## 2. 本案例你能学到什么？
- spot price 与 reserve 之间的关系、以及“流动性越小 → 价格越容易被推走”
- 为什么 **spot oracle ≠ 安全 oracle**
- 如何写“攻击前后价格断言”：  
  - `assertGt(priceAfter, priceBefore * 2)` 或 bps 偏移断言
- 如何写“攻击前后借款上限断言”：  
  - vuln：`maxBorrowAfter > maxBorrowBefore`
  - fixed：`maxBorrowAfter ≈ maxBorrowBefore`（同区块推价不应立刻改变）
- TWAP（时间加权平均价）的原理与最小实现：  
  - `priceCumulative += price * timeElapsed`  
  - `twap = (cumNow - cumOld) / timeElapsed`

---

## 3. 漏洞版本：spot price 借贷（可被操纵）

> 场景：抵押 token0 借 token1。借款上限取决于 AMM 的 `spotPrice0In1()`  
> 问题：攻击者可以 swap 推高 spot，从而**抬高抵押价值** → 借到更多 token1。

### 3.1 最小 ERC20：`SimpleERC20.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SimpleERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(string memory n, string memory s) {
        name = n; symbol = s;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
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
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
```

### 3.2 最小 x*y=k AMM：`SimpleAMMXYK.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleERC20} from "../tokens/SimpleERC20.sol";

contract SimpleAMMXYK {
    SimpleERC20 public immutable token0;
    SimpleERC20 public immutable token1;

    uint112 public reserve0;
    uint112 public reserve1;

    error InsufficientLiquidity();
    error BadToken();

    constructor(SimpleERC20 _t0, SimpleERC20 _t1) {
        token0 = _t0;
        token1 = _t1;
    }

    function _update(uint256 r0, uint256 r1) internal {
        reserve0 = uint112(r0);
        reserve1 = uint112(r1);
    }

    function addLiquidity(uint256 amount0, uint256 amount1) external {
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);

        uint256 r0 = uint256(reserve0) + amount0;
        uint256 r1 = uint256(reserve1) + amount1;
        _update(r0, r1);
    }

    // spot price：token0 以 token1 计价
    function spotPrice0In1() public view returns (uint256) {
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();
        return (uint256(reserve1) * 1e18) / uint256(reserve0);
    }

    function swapExactIn(address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        if (tokenIn != address(token0) && tokenIn != address(token1)) revert BadToken();
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();

        bool inIs0 = tokenIn == address(token0);
        SimpleERC20 inToken = inIs0 ? token0 : token1;
        SimpleERC20 outToken = inIs0 ? token1 : token0;

        uint256 rIn  = inIs0 ? uint256(reserve0) : uint256(reserve1);
        uint256 rOut = inIs0 ? uint256(reserve1) : uint256(reserve0);

        inToken.transferFrom(msg.sender, address(this), amountIn);

        uint256 k = rIn * rOut;
        uint256 newRIn = rIn + amountIn;
        uint256 newROut = k / newRIn;
        amountOut = rOut - newROut;

        outToken.transfer(msg.sender, amountOut);

        if (inIs0) _update(newRIn, newROut);
        else _update(newROut, newRIn);
    }
}
```

### 3.3 漏洞借贷：`D45_SpotOracleLendingVuln.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleERC20} from "../tokens/SimpleERC20.sol";
import {SimpleAMMXYK} from "../amm/SimpleAMMXYK.sol";

contract D45_SpotOracleLendingVuln {
    SimpleERC20 public immutable collateral; // token0
    SimpleERC20 public immutable debt;       // token1
    SimpleAMMXYK public immutable amm;

    uint256 public constant LTV_BPS = 5000; // 50%
    uint256 public constant BPS = 10_000;

    mapping(address => uint256) public collateralOf;
    mapping(address => uint256) public debtOf;

    error ExceedsBorrowLimit(uint256 want, uint256 max);

    constructor(SimpleERC20 _collateral, SimpleERC20 _debt, SimpleAMMXYK _amm) {
        collateral = _collateral;
        debt = _debt;
        amm = _amm;
    }

    function depositCollateral(uint256 amount) external {
        collateral.transferFrom(msg.sender, address(this), amount);
        collateralOf[msg.sender] += amount;
    }

    // ❌ 漏洞：maxBorrow 使用 spot price（可被同区块操纵）
    function maxBorrow(address user) public view returns (uint256) {
        uint256 price0In1 = amm.spotPrice0In1(); // 1e18 scale
        uint256 valueInDebt = (collateralOf[user] * price0In1) / 1e18;
        return (valueInDebt * LTV_BPS) / BPS;
    }

    function borrow(uint256 amount) external {
        uint256 maxB = maxBorrow(msg.sender);
        if (debtOf[msg.sender] + amount > maxB) revert ExceedsBorrowLimit(amount, maxB);
        debtOf[msg.sender] += amount;
        debt.transfer(msg.sender, amount);
    }
}
```

---

## 4. 漏洞攻击测试：攻击前后价格断言 + 借款上限断言

> 关键点：swap 会消耗 attacker 的 tokenIn（例如 t1），所以余额断言要用“借款前后差值”而不是硬编码初始余额。

### 4.1 攻击测试：`test/vulns/D45_PriceManipulation.t.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {SimpleERC20} from "../../src/tokens/SimpleERC20.sol";
import {SimpleAMMXYK} from "../../src/amm/SimpleAMMXYK.sol";
import {D45_SpotOracleLendingVuln} from "../../src/vulns/D45_SpotOracleLendingVuln.sol";

contract D45_PriceManipulation_Test is Test {
    SimpleERC20 t0; // collateral
    SimpleERC20 t1; // debt
    SimpleAMMXYK amm;
    D45_SpotOracleLendingVuln lend;

    address lp = makeAddr("lp");
    address attacker = makeAddr("attacker");

    function setUp() public {
        t0 = new SimpleERC20("Token0", "T0");
        t1 = new SimpleERC20("Token1", "T1");

        amm = new SimpleAMMXYK(t0, t1);
        lend = new D45_SpotOracleLendingVuln(t0, t1, amm);

        // 初始资金
        t0.mint(lp, 1_000 ether);
        t1.mint(lp, 1_000 ether);

        t0.mint(attacker, 1_000 ether);
        t1.mint(attacker, 1_000 ether);

        // 借贷池给足可借出的 t1
        t1.mint(address(lend), 10_000 ether);

        // 建一个“很小”的池子：100:100（低流动性）
        vm.startPrank(lp);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        amm.addLiquidity(100 ether, 100 ether);
        vm.stopPrank();

        // attacker 抵押 10 T0
        vm.startPrank(attacker);
        t0.approve(address(lend), type(uint256).max);
        lend.depositCollateral(10 ether);
        vm.stopPrank();
    }

    function test_attack_manipulates_spot_price_and_increases_borrow_limit() public {
        uint256 priceBefore = amm.spotPrice0In1();
        uint256 maxBorrowBefore = lend.maxBorrow(attacker);

        // 初始价格接近 1（100:100）
        assertApproxEqAbs(priceBefore, 1e18, 1e14);

        // 攻击：用大量 t1 买 t0（使 reserve0 变小 → price0In1 = reserve1/reserve0 变大）
        vm.startPrank(attacker);
        t1.approve(address(amm), type(uint256).max);
        amm.swapExactIn(address(t1), 90 ether);
        vm.stopPrank();

        uint256 priceAfter = amm.spotPrice0In1();
        uint256 maxBorrowAfter = lend.maxBorrow(attacker);

        // ✅ 核心断言 1：spot 被明显推高
        assertGt(priceAfter, priceBefore * 2);

        // ✅ 核心断言 2：借款上限变大（spot 被操纵影响估值）
        assertGt(maxBorrowAfter, maxBorrowBefore);

        // ✅ 借款余额断言：用借款前后差值（避免被 swap 消耗的 t1 影响）
        uint256 extra = maxBorrowAfter - maxBorrowBefore;

        uint256 balBeforeBorrow = t1.balanceOf(attacker);
        vm.startPrank(attacker);
        lend.borrow(extra);
        vm.stopPrank();

        assertEq(t1.balanceOf(attacker), balBeforeBorrow + extra);
    }
}
```

### 4.2 审计味更强：价格偏移 bps 断言（可选）
```solidity
uint256 movedBps = (priceAfter > priceBefore)
    ? ((priceAfter - priceBefore) * 10_000 / priceBefore)
    : ((priceBefore - priceAfter) * 10_000 / priceBefore);
assertGt(movedBps, 5_000); // 偏移超过 50%
```

运行：
```bash
cd labs/foundry-labs
forge test --match-contract D45_PriceManipulation_Test -vvv
```

---

## 5. 修复：TWAP 原理（时间加权平均价）

### 5.1 TWAP 直觉
把一段时间内的价格按“持续时间”做平均：

- 攻击者把 spot 拉爆 1 秒，只占 30 分钟窗口的 1/1800，平均价几乎不动  
- 想让 TWAP 明显变化，必须把歪价维持很久 → 成本巨大、容易被套利对手盘打回

### 5.2 工程实现（累计面积）
维护累计值：
- `priceCumulative += price * timeElapsed`

然后窗口均价：
- `TWAP = (cumNow - cumOld) / timeElapsed`

---

## 6. 修复代码：AMM 加 TWAP 累计 + 借贷用 TWAP

### 6.1 AMM（带 TWAP 累计）：`SimpleAMMXYK_TWAP.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleERC20} from "../tokens/SimpleERC20.sol";

contract SimpleAMMXYK_TWAP {
    SimpleERC20 public immutable token0;
    SimpleERC20 public immutable token1;

    uint112 public reserve0;
    uint112 public reserve1;

    uint32 public blockTimestampLast;
    uint256 public price0Cumulative; // (price0In1 * seconds) 累加，price 用 1e18

    error InsufficientLiquidity();
    error BadToken();

    constructor(SimpleERC20 _t0, SimpleERC20 _t1) {
        token0 = _t0;
        token1 = _t1;
        blockTimestampLast = uint32(block.timestamp);
    }

    function spotPrice0In1() public view returns (uint256) {
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();
        return (uint256(reserve1) * 1e18) / uint256(reserve0);
    }

    function _update(uint256 newR0, uint256 newR1) internal {
        uint32 ts = uint32(block.timestamp);
        uint32 elapsed = ts - blockTimestampLast;
        if (elapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            uint256 p0 = (uint256(reserve1) * 1e18) / uint256(reserve0);
            price0Cumulative += p0 * elapsed;
        }
        blockTimestampLast = ts;

        reserve0 = uint112(newR0);
        reserve1 = uint112(newR1);
    }

    function addLiquidity(uint256 amount0, uint256 amount1) external {
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);

        uint256 r0 = uint256(reserve0) + amount0;
        uint256 r1 = uint256(reserve1) + amount1;
        _update(r0, r1);
    }

    function swapExactIn(address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        if (tokenIn != address(token0) && tokenIn != address(token1)) revert BadToken();
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();

        bool inIs0 = tokenIn == address(token0);
        SimpleERC20 inToken = inIs0 ? token0 : token1;
        SimpleERC20 outToken = inIs0 ? token1 : token0;

        uint256 rIn  = inIs0 ? uint256(reserve0) : uint256(reserve1);
        uint256 rOut = inIs0 ? uint256(reserve1) : uint256(reserve0);

        inToken.transferFrom(msg.sender, address(this), amountIn);

        uint256 k = rIn * rOut;
        uint256 newRIn = rIn + amountIn;
        uint256 newROut = k / newRIn;
        amountOut = rOut - newROut;

        outToken.transfer(msg.sender, amountOut);

        if (inIs0) _update(newRIn, newROut);
        else _update(newROut, newRIn);
    }
}
```

### 6.2 借贷（改用 TWAP）：`D45_SpotOracleLendingFixed_TWAP.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleERC20} from "../tokens/SimpleERC20.sol";
import {SimpleAMMXYK_TWAP} from "../amm/SimpleAMMXYK_TWAP.sol";

contract D45_SpotOracleLendingFixed_TWAP {
    SimpleERC20 public immutable collateral; // token0
    SimpleERC20 public immutable debt;       // token1
    SimpleAMMXYK_TWAP public immutable amm;

    uint256 public constant LTV_BPS = 5000;
    uint256 public constant BPS = 10_000;

    uint256 public lastPrice0Cumulative;
    uint32  public lastTimestamp;
    uint32  public constant MIN_WINDOW = 30 minutes;

    mapping(address => uint256) public collateralOf;
    mapping(address => uint256) public debtOf;

    error ExceedsBorrowLimit(uint256 want, uint256 max);
    error TWAPNotReady(uint32 elapsed, uint32 minWindow);

    constructor(SimpleERC20 _c, SimpleERC20 _d, SimpleAMMXYK_TWAP _amm) {
        collateral = _c;
        debt = _d;
        amm = _amm;

        lastPrice0Cumulative = _amm.price0Cumulative();
        lastTimestamp = _amm.blockTimestampLast();
    }

    function updateOracle() public {
        lastPrice0Cumulative = amm.price0Cumulative();
        lastTimestamp = amm.blockTimestampLast();
    }

    function twapPrice0In1() public view returns (uint256) {
        uint256 curC = amm.price0Cumulative();
        uint32 curTs = amm.blockTimestampLast();

        uint32 elapsed = curTs - lastTimestamp;
        if (elapsed < MIN_WINDOW) revert TWAPNotReady(elapsed, MIN_WINDOW);

        return (curC - lastPrice0Cumulative) / elapsed; // 1e18 scale
    }

    function depositCollateral(uint256 amount) external {
        collateral.transferFrom(msg.sender, address(this), amount);
        collateralOf[msg.sender] += amount;
    }

    function maxBorrow(address user) public view returns (uint256) {
        uint256 price0In1 = twapPrice0In1();
        uint256 valueInDebt = (collateralOf[user] * price0In1) / 1e18;
        return (valueInDebt * LTV_BPS) / BPS;
    }

    function borrow(uint256 amount) external {
        uint256 maxB = maxBorrow(msg.sender);
        if (debtOf[msg.sender] + amount > maxB) revert ExceedsBorrowLimit(amount, maxB);
        debtOf[msg.sender] += amount;
        debt.transfer(msg.sender, amount);
    }
}
```

---

## 7. 修复回归测试：同区块推 spot 不应立刻改变 TWAP 借款上限

> 关键坑：**只 warp 不会累计**，必须触发 AMM 的 `_update`（例如加 1 wei 流动性）把 `price * elapsed` 计入 cumulative。

### 7.1 Fixed 测试：`test/vulns/D45_PriceManipulation_Fixed.t.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {SimpleERC20} from "../../src/tokens/SimpleERC20.sol";
import {SimpleAMMXYK_TWAP} from "../../src/amm/SimpleAMMXYK_TWAP.sol";
import {D45_SpotOracleLendingFixed_TWAP} from "../../src/fixed/D45_SpotOracleLendingFixed_TWAP.sol";

contract D45_PriceManipulation_Fixed_Test is Test {
    SimpleERC20 t0;
    SimpleERC20 t1;
    SimpleAMMXYK_TWAP amm;
    D45_SpotOracleLendingFixed_TWAP lend;

    address lp = makeAddr("lp");
    address attacker = makeAddr("attacker");

    function setUp() public {
        t0 = new SimpleERC20("Token0", "T0");
        t1 = new SimpleERC20("Token1", "T1");

        amm = new SimpleAMMXYK_TWAP(t0, t1);
        lend = new D45_SpotOracleLendingFixed_TWAP(t0, t1, amm);

        t0.mint(lp, 1_000 ether);
        t1.mint(lp, 1_000 ether);

        t0.mint(attacker, 1_000 ether);
        t1.mint(attacker, 1_000 ether);

        t1.mint(address(lend), 10_000 ether);

        vm.startPrank(lp);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        amm.addLiquidity(100 ether, 100 ether);
        vm.stopPrank();

        vm.startPrank(attacker);
        t0.approve(address(lend), type(uint256).max);
        lend.depositCollateral(10 ether);
        vm.stopPrank();
    }

    function _bumpAMM() internal {
        vm.startPrank(lp);
        amm.addLiquidity(1, 1); // 触发 _update → cumulative 前进
        vm.stopPrank();
    }

    function test_fixed_twap_resists_sameBlock_spot_manipulation() public {
        // 1) 先过时间并推进 cumulative
        vm.warp(block.timestamp + 10 minutes);
        _bumpAMM();

        // 2) 记录 observation
        lend.updateOracle();

        // 3) 再过 MIN_WINDOW 并推进 cumulative
        vm.warp(block.timestamp + 30 minutes);
        _bumpAMM();

        uint256 maxBorrowBefore = lend.maxBorrow(attacker);

        // 4) 攻击者推 spot（不 warp，同一时间点）
        vm.startPrank(attacker);
        t1.approve(address(amm), type(uint256).max);
        amm.swapExactIn(address(t1), 90 ether);
        vm.stopPrank();

        uint256 maxBorrowAfter = lend.maxBorrow(attacker);

        // ✅ 核心断言：同区块推 spot 不应立刻显著抬高 TWAP 借款上限
        assertApproxEqAbs(maxBorrowAfter, maxBorrowBefore, 1e12);

        // 5) 试图多借应该失败
        vm.startPrank(attacker);
        vm.expectRevert();
        lend.borrow(maxBorrowBefore + 1 ether);
        vm.stopPrank();
    }
}
```

运行：
```bash
cd labs/foundry-labs
forge test --match-contract D45_PriceManipulation_Fixed_Test -vvv
```

---

## 8. 审计视角 Checklist（D45）

### 8.1 风险信号（看到就要警惕）
- 价格来源是 DEX/AMM 的 **spot**：`getReserves()` / `spotPrice()` / `getAmountsOut()`  
- 在同一笔交易中，攻击者可以先 swap 改变价格，再调用依赖价格的逻辑
- 价格用于高价值决策：
  - 抵押借贷（LTV / 借款上限 / health factor）
  - 清算（liquidation）
  - mint/burn 定价
  - 赎回/兑换比例

### 8.2 防护策略（从易到难）
- ✅ **TWAP**：窗口 >= 15~30 分钟（视业务风险而定）
- ✅ 最小流动性门槛：池子太小不作为 oracle
- ✅ 偏离阈值：`abs(spot - twap) <= maxDeviationBps` 否则拒绝
- ✅ 多源预言机：Chainlink + DEX TWAP 交叉验证
- ✅ 延迟/两步提交：价格采样与使用分离

### 8.3 测试点（写成回归用例）
- [ ] 小池子大额 swap → spot 偏移 bps 超阈值（可复现）
- [ ] vuln：spot 偏移后 `maxBorrow` 立刻变大
- [ ] fixed：同区块推 spot，`maxBorrow` 不应显著变大
- [ ] fixed：窗口未满足，调用 `maxBorrow` 应 revert（TWAPNotReady）

---

## 9. 常见坑（你很可能会踩到）
- **只 vm.warp 不触发 AMM update**：cumulative 不会变；必须有 `_update()`（addLiquidity(1,1) 或 swap）
- fixed 版本 **updateOracle 后没等够 MIN_WINDOW**：会触发 `TWAPNotReady`
- 测试里断言用 `==` 太死：中间有 bump 会有微小变化，建议 `assertApproxEqAbs`

---

## 10. 建议文件路径（可按你的 repo 调整）
- `labs/foundry-labs/src/tokens/SimpleERC20.sol`
- `labs/foundry-labs/src/amm/SimpleAMMXYK.sol`
- `labs/foundry-labs/src/amm/SimpleAMMXYK_TWAP.sol`
- `labs/foundry-labs/src/vulns/D45_SpotOracleLendingVuln.sol`
- `labs/foundry-labs/src/fixed/D45_SpotOracleLendingFixed_TWAP.sol`
- `labs/foundry-labs/test/vulns/D45_PriceManipulation.t.sol`
- `labs/foundry-labs/test/vulns/D45_PriceManipulation_Fixed.t.sol`
