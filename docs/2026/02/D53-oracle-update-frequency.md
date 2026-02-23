# D53：Oracle 更新频率 / 价格跳变 —— “更新前后清算条件变化”测试

> 目标：用最小借贷模型 + Mock Oracle，写出 **Oracle 更新前后**“是否可清算”状态发生变化的测试；并补充审计视角与“升级一档”的扩展练习。

---

## 1. 背景与动机（通俗理解）

借贷协议的清算判断，本质上是比较两件事：

- **抵押品价值（按 Oracle 价格换算）**
- **债务价值**

常见判断形态（概念层面）：

> 抵押价值 × 清算阈值（Liquidation Threshold） < 债务  ⇒  可清算

但 Oracle **不是连续实时更新**，而是“隔一段时间喂一次价”（更新频率 / heartbeat）：

- **更新前**：协议仍看到旧价格，可能“看起来安全”
- **更新后**：价格跳到新值，可能“立刻变成可清算”
- 同理也可能反过来：更新后价格反弹，变为“不该清算”

D53 就是在测试中把这种“**更新前后清算条件变化**”固定住，写成可回归的断言。

---

## 2. 你将学到什么

1. **清算触发条件**如何计算（抵押价值、阈值折扣、债务比较）。
2. **Oracle 更新频率 / 价格陈旧（stale）**对系统的影响：
   - 旧价格可能导致 **该清算却不清算** / **误清算**
3. Foundry 测试技巧：
   - 用 `vm.warp` 模拟时间流逝（影响价格 freshness）
   - 写“更新前不满足 / 更新后满足”的 **对比断言**
4. 审计视角重点：
   - 是否检查 `updatedAt`（heartbeat/maxDelay）
   - 对“价格跳变”是否有保护（maxDeviation / circuit breaker）
   - 采用 spot 还是 TWAP（抗操纵 vs 延迟）

---

## 3. 知识点与原理（核心公式）

### 3.1 单位与精度（WAD = 1e18）

在 Solidity 中常用 `1e18` 作为“定点小数”的缩放因子：

- 价格 `priceE18`：例如 ETH=2000，则存为 `2000e18`
- 抵押数量 `collateralEth`：1 ETH 存为 `1e18`
- USD 债务 `debtUsd`：例如 1200 USD 存为 `1200e18`

#### 抵押价值（USD）计算

```
collateralValueUsd = collateralEth * priceE18 / 1e18
```

### 3.2 清算阈值（Liquidation Threshold / LTV 的一种表达）

清算阈值记为 `liqThresholdE18`，例如 80%：

- `liqThresholdE18 = 0.8e18`

折扣后的抵押价值：

```
discounted = collateralValueUsd * liqThresholdE18 / 1e18
```

清算判断：

```
discounted < debtUsd  => liquidatable
```

### 3.3 “更新频率/陈旧价”问题（stale price）

Oracle 往往包含 `updatedAt`：

- 如果 `block.timestamp > updatedAt + maxDelay`  
  则价格可能过期（stale），继续使用会有风险。

常见策略：

- **严格模式**：过期直接 `revert`（阻断借贷/清算判断）
- **降级模式**：回退到 TWAP / 上一次可信价格 / 暂停关键功能

D53 的基础版本用严格模式：`isLiquidatable()` 内部先检查 freshness。

---

## 4. 最小实现（合约 + 测试）

> 文件建议（按你仓库习惯可调整）：
- `src/D53_OracleUpdate.sol`
- `test/vulns/D53_OracleUpdateFrequency.t.sol`

### 4.1 合约：MockOracle + SimpleLending

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockOracle {
    uint256 public priceE18;
    uint256 public updatedAt;

    event PriceUpdated(uint256 priceE18, uint256 updatedAt);

    function update(uint256 newPriceE18) external {
        priceE18 = newPriceE18;
        updatedAt = block.timestamp;
        emit PriceUpdated(newPriceE18, updatedAt);
    }

    function getPrice() external view returns (uint256) {
        return priceE18;
    }
}

contract SimpleLending {
    uint256 public constant WAD = 1e18;

    MockOracle public immutable oracle;
    uint256 public immutable liquidationThresholdE18; // e.g. 0.8e18
    uint256 public immutable maxOracleDelay;          // e.g. 3600

    mapping(address => uint256) public collateralEth;
    mapping(address => uint256) public debtUsd;

    error StalePrice(uint256 updatedAt, uint256 nowTs);

    constructor(MockOracle _oracle, uint256 _liqThresholdE18, uint256 _maxOracleDelay) {
        oracle = _oracle;
        liquidationThresholdE18 = _liqThresholdE18;
        maxOracleDelay = _maxOracleDelay;
    }

    function depositCollateral(uint256 ethAmountE18) external {
        collateralEth[msg.sender] += ethAmountE18;
    }

    function borrow(uint256 usdAmountE18) external {
        // D53 聚焦清算判断变化：这里可先不做风控校验
        debtUsd[msg.sender] += usdAmountE18;
    }

    function _priceFresh() internal view {
        uint256 t = oracle.updatedAt();
        if (block.timestamp > t + maxOracleDelay) {
            revert StalePrice(t, block.timestamp);
        }
    }

    function collateralValueUsd(address user) public view returns (uint256) {
        uint256 p = oracle.priceE18();
        return (collateralEth[user] * p) / WAD;
    }

    function isLiquidatable(address user) external view returns (bool) {
        _priceFresh();
        uint256 value = collateralValueUsd(user);
        uint256 discounted = (value * liquidationThresholdE18) / WAD;
        return discounted < debtUsd[user];
    }
}
```

### 4.2 测试：更新前后清算条件变化 + 陈旧价阻断

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/D53_OracleUpdate.sol";

contract D53_OracleUpdateFrequency_Test is Test {
    address alice = makeAddr("alice");

    MockOracle oracle;
    SimpleLending lending;

    function setUp() public {
        oracle = new MockOracle();
        lending = new SimpleLending(oracle, 0.8e18, 3600);

        // 初始喂价：ETH=2000
        oracle.update(2000e18);

        // 抵押 1 ETH
        vm.prank(alice);
        lending.depositCollateral(1e18);

        // 借 1200 USD（安全：2000*0.8=1600 > 1200）
        vm.prank(alice);
        lending.borrow(1200e18);
    }

    function test_update_before_after_liquidation_condition_changes() public {
        // 更新前：不该清算
        assertEq(lending.isLiquidatable(alice), false);

        // 时间过去，但 oracle 不更新：状态不变（仍旧价）
        vm.warp(block.timestamp + 300);
        assertEq(lending.isLiquidatable(alice), false);

        // 价格跳变：2000 -> 1300
        // 折后：1300*0.8=1040 < 1200 => 可清算
        oracle.update(1300e18);
        assertEq(lending.isLiquidatable(alice), true);

        // 再反弹：1300 -> 2200
        // 折后：2200*0.8=1760 > 1200 => 不可清算
        oracle.update(2200e18);
        assertEq(lending.isLiquidatable(alice), false);
    }

    function test_stale_price_reverts_and_blocks_liquidation_check() public {
        // 超过 maxOracleDelay
        vm.warp(block.timestamp + 3601);
        vm.expectRevert(SimpleLending.StalePrice.selector);
        lending.isLiquidatable(alice);
    }
}
```

### 4.3 运行命令

```bash
forge test --match-contract D53_OracleUpdateFrequency_Test -vvv
```

---

## 5. 审计视角（Checklist）

### 5.1 Oracle Freshness（陈旧价）

- [ ] 是否使用 `updatedAt` / heartbeat 检查价格是否过期？
- [ ] `maxDelay` 设置是否合理（过大 = 风险窗口长；过小 = 可用性差）？
- [ ] 过期时策略：
  - [ ] `revert`（阻断借贷/清算判断）
  - [ ] fallback（TWAP / last-good-price / pause）

### 5.2 价格跳变（Jump / Deviation）

- [ ] 是否限制单次更新最大偏移（`maxDeviationBps`）？
- [ ] 是否有熔断器（circuit breaker）：跳变过大暂停借贷/清算？
- [ ] 是否存在“喂价权限”风险（oracle updater 权限、治理延迟、紧急暂停）？

### 5.3 Spot vs TWAP（抗操纵）

- [ ] 清算/借贷是否依赖**瞬时 spot**（易被操纵）？
- [ ] 是否采用 TWAP（更稳但有滞后）？
- [ ] TWAP 窗口与更新频率是否匹配？（窗口太短仍可操纵；太长反应慢）

### 5.4 清算边界抖动与用户体验

- [ ] 价格在边界附近上下跳，是否可能出现误清算？
- [ ] 是否需要 buffer（更保守阈值/双阈值）或最小间隔（cooldown）？

---

## 6. D53 升级一档（建议扩展练习）

> 目标：不仅验证“更新前后清算条件变化”，还要模拟“**更新频率约束** / **跳变保护** / **TWAP**”三类真实系统常见机制。

下面给出三种升级路线（从易到难），你可以选其中一个或组合：

### A) 增加最小更新间隔（minUpdateInterval）

**动机**：现实喂价并不会每秒更新；你可以在测试里体现“必须等到下一次允许更新”。

**实现思路**：
- Oracle 存 `minUpdateInterval`，若 `block.timestamp < updatedAt + minUpdateInterval` 则 `update()` revert。
- 测试：
  1) 先尝试过早更新，应 revert  
  2) warp 到间隔后更新成功  
  3) 更新成功后清算状态发生变化

伪代码（Oracle 部分）：

```solidity
uint256 public minUpdateInterval;
error UpdateTooFrequent();

function update(uint256 newPriceE18) external {
    if (updatedAt != 0 && block.timestamp < updatedAt + minUpdateInterval) {
        revert UpdateTooFrequent();
    }
    priceE18 = newPriceE18;
    updatedAt = block.timestamp;
}
```

### B) 增加跳变限制（maxDeviationBps）+ 熔断（pause）

**动机**：价格从 2000 跳到 200（-90%）可能是异常或攻击，应触发保护。

**实现思路**：
- 计算偏移：`abs(new-old)/old`，超过阈值则：
  - 方案1：revert 更新
  - 方案2：标记 `paused=true`，协议关键操作 revert（更像熔断）
- 测试：
  - 喂一个“超大跳变”，断言触发 `paused` 或 update revert
  - 进一步断言协议 `isLiquidatable` 或 `borrow` 被阻断

### C) 用简化 TWAP 替代 spot（两点平均 or 滑动平均）

**动机**：spot 太容易被 DEX 小池子操纵；TWAP 降低被瞬时拉价影响。

**实现思路（最简版）**：
- Oracle 维护 `lastPrice` 与 `price`，TWAP 用 `(lastPrice + price)/2`
- 每次 update：`lastPrice = price; price = newPrice;`
- 协议用 TWAP 作为 `getPrice()` 返回值
- 测试：
  - 先喂高价，再喂低价  
  - spot 会立刻触发清算，但 TWAP 可能仍未触发（或触发更晚）  
  - 写出两套断言对比（这是很好的审计/面试点）

---

## 7. 建议的提交结构与命名

- `src/D53_OracleUpdate.sol`
- `test/vulns/D53_OracleUpdateFrequency.t.sol`
- `docs/2026/02/D53-oracle-update-frequency.md`
- `docs/2026/02/INDEX.md`（追加索引条目）

---

## 8. 小结

D53 的本质是：**用测试把“价格更新/跳变/陈旧”对清算判断的影响固化为断言**。  
在真实协议审计中，这一类问题经常出现在：
- 没做 freshness（stale price）
- 用 spot 做关键风控（可操纵）
- 没有限制跳变/没熔断（异常价穿透风控）

升级一档后，你能把 D53 从“能跑的最小例子”提升到“更贴近真实协议的风控策略测试”。

