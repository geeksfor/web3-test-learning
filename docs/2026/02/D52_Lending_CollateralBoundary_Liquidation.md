# D52：借贷场景——抵押率边界 / 清算触发（简化模型）

> 目标：用一个“最小借贷池 + 可控价格 Oracle”的简化模型，练习 **抵押率边界（LTV）**、**清算阈值（LT）**、**价格下跌触发清算**、以及 **清算后状态断言**。  
> 本文包含：知识点与原理、审计视角、详细步骤与代码、以及本次对话中的提问 Q&A（含 WAD 单位换算、清算机制与日志调试）。

---

## 1. 知识点与原理（通俗易懂）

### 1.1 抵押价值、债务价值、LTV 与清算阈值 LT

把用户仓位抽象成两件事：

- **抵押品价值**：`collateralValue = collateralAmount * price`
- **债务价值**：`debtValue = debtAmount * debtPrice`（本文简化为 debt token = $1）

两条核心规则：

- **可借上限（LTV）**  
  `debtValue <= collateralValue * LTV`  
  LTV 用来限制“最多能借多少”，例如 75%。

- **清算触发（LT）**  
  `debtValue > collateralValue * LT` → 可被清算  
  LT 用来判断“什么时候不安全到需要强制降低风险”，例如 80%。

> 常见设计：`LT > LTV`  
> - LTV：借款上限（更保守）  
> - LT：清算阈值（更宽松）  
> 这样留出缓冲区，避免“刚借完就触发清算”。

### 1.2 为什么要有“清算人”？

如果只允许“谁借的谁还”，当价格暴跌仓位不健康时：

- 借款人可能 **不愿还** 或 **没能力还**  
- 协议会“干等”，抵押继续跌 → 产生坏账，损失由存款人/协议承担

所以需要市场化机制：**任何人（清算人）都可以替借款人还一部分债（repay），并拿走借款人的抵押（seize）+ 奖励（bonus）**，让风险仓位尽快回到安全区。

### 1.3 清算时为什么“清算人还债”，不是借款人还？

清算不是“借给你钱让你以后还他”，而是一次性交换：

- 清算人：付出稳定币（repay）
- 协议：减少借款人债务（debt↓）
- 清算人：立即获得抵押品（seize）并带奖励

因此 **你一般不需要“再还清算人钱”**，你付出的代价是：**抵押品被扣走**。

---

## 2. WAD 单位换算（避免迷糊的通用模板）

Solidity 没有小数，所以把比例/价格等用 `WAD=1e18` 放大为整数计算。

### 2.1 典型模板（强烈建议记住）

- **数量(18位) × 价格(18位) → 价值(18位)**  
  `valueWad = amountWad * priceWad / 1e18`

- **价值(18位) ÷ 价格(18位) → 数量(18位)**  
  `amountWad = valueWad * 1e18 / priceWad`

- **价值(18位) × 比例(18位) → 部分价值(18位)**  
  `partWad = valueWad * ratioWad / 1e18`

### 2.2 为什么要 `/WAD`？

因为“两个 18 位精度的数相乘会多出一个 1e18”，你想让结果仍保持 18 位，就要除掉一次 `1e18` 把尺度拉回去。

---

## 3. 审计视角 Checklist（D52 重点）

1. **单位与精度统一**：amount/price/ratio 都是 18 位吗？是否出现“多乘或少除一次 WAD”的 e36 异常？
2. **边界符号**：  
   - 借款检查 `>` vs `>=`（刚好等于上限能否借？）  
   - 清算触发 `>` vs `>=`（刚好等于阈值能否被清算？）
3. **LTV 与 LT 配置**：是否 `LT > LTV`？否则可能刚借完就可清算。
4. **清算上限 closeFactor**：是否限制单次 repay？是否可一次性清空导致极端抢跑/过度惩罚？
5. **bonus 计算正确性**：`seizeValue = repayValue * (1 + bonus)`；是否溢出/舍入方向是否合理？
6. **Oracle 风险**：价格是否可被操纵（本文故意可控用于测试）；真实系统需 TWAP/多源/限幅等。
7. **转账顺序与重入**：真实协议应考虑 reentrancy 与“先记账后转账”的顺序。

---

## 4. 详细操作步骤（Foundry）

### Step 0：文件结构建议

- `src/D52_SimpleLending.sol`
- `test/D52_CollateralBoundaryAndLiquidation.t.sol`

### Step 1：实现最小借贷池 + 可控 Oracle

> 说明：下面版本把“债务 token = $1”的价值处理写得更自洽：  
> - `debtOf[user]` 本身就是 18 位的“美元 WAD”数量（例如 1500e18 代表 $1500）  
> - 因此 `debtValueUsdWad = debtOf[user]`（不再额外乘 WAD）

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

contract D52_OracleMock {
    // price in WAD, e.g. 2000e18 means $2000 per collateral token
    uint256 public priceWad;
    function setPrice(uint256 newPriceWad) external { priceWad = newPriceWad; }
}

contract D52_SimpleLending {
    uint256 internal constant WAD = 1e18;

    error NotHealthy(uint256 debtValueUsdWad, uint256 maxDebtValueUsdWad);
    error NotLiquidatable();
    error RepayTooMuch(uint256 maxRepayWad);
    error Zero();

    IERC20 public immutable collateralToken;
    IERC20 public immutable debtToken; // simplified $1 stable
    D52_OracleMock public immutable oracle;

    uint256 public immutable ltvWad;         // e.g. 0.75e18
    uint256 public immutable ltWad;          // e.g. 0.80e18
    uint256 public immutable closeFactorWad; // e.g. 0.50e18
    uint256 public immutable bonusWad;       // e.g. 0.05e18

    mapping(address => uint256) public collateralOf; // amountWad
    mapping(address => uint256) public debtOf;       // debtWad (also USD valueWad)

    constructor(
        IERC20 _collateralToken,
        IERC20 _debtToken,
        D52_OracleMock _oracle,
        uint256 _ltvWad,
        uint256 _ltWad,
        uint256 _closeFactorWad,
        uint256 _bonusWad
    ) {
        collateralToken = _collateralToken;
        debtToken = _debtToken;
        oracle = _oracle;
        ltvWad = _ltvWad;
        ltWad = _ltWad;
        closeFactorWad = _closeFactorWad;
        bonusWad = _bonusWad;
    }

    function deposit(uint256 amountWad) external {
        if (amountWad == 0) revert Zero();
        collateralToken.transferFrom(msg.sender, address(this), amountWad);
        collateralOf[msg.sender] += amountWad;
    }

    function borrow(uint256 amountWad) external {
        if (amountWad == 0) revert Zero();

        uint256 newDebtWad = debtOf[msg.sender] + amountWad;

        uint256 colValueUsdWad = collateralValueUsdWad(msg.sender);
        uint256 maxDebtUsdWad = colValueUsdWad * ltvWad / WAD;

        // debt token assumed $1 => debtValueUsdWad == debtWad
        uint256 newDebtValueUsdWad = newDebtWad;

        if (newDebtValueUsdWad > maxDebtUsdWad) {
            revert NotHealthy(newDebtValueUsdWad, maxDebtUsdWad);
        }

        debtOf[msg.sender] = newDebtWad;
        debtToken.transfer(msg.sender, amountWad);
    }

    function isLiquidatable(address user) public view returns (bool) {
        uint256 debtValueUsdWad = debtOf[user]; // $1 stable
        uint256 thresholdUsdWad = collateralValueUsdWad(user) * ltWad / WAD;
        return debtValueUsdWad > thresholdUsdWad; // boundary: equals => NOT liquidatable
    }

    function liquidate(address user, uint256 repayWad) external {
        if (!isLiquidatable(user)) revert NotLiquidatable();
        if (repayWad == 0) revert Zero();

        uint256 userDebtWad = debtOf[user];
        uint256 maxRepayWad = userDebtWad * closeFactorWad / WAD;
        if (repayWad > maxRepayWad) revert RepayTooMuch(maxRepayWad);

        // liquidator repays with stablecoin
        debtToken.transferFrom(msg.sender, address(this), repayWad);
        debtOf[user] = userDebtWad - repayWad;

        // seizeValue = repayValue * (1 + bonus)
        // repayValueUsdWad == repayWad
        uint256 seizeValueUsdWad = repayWad * (WAD + bonusWad) / WAD;

        // seizeAmount = seizeValue / price
        uint256 priceUsdPerColWad = oracle.priceWad();
        uint256 seizeAmountWad = seizeValueUsdWad * WAD / priceUsdPerColWad;

        uint256 userColWad = collateralOf[user];
        if (seizeAmountWad > userColWad) seizeAmountWad = userColWad;

        collateralOf[user] = userColWad - seizeAmountWad;
        collateralToken.transfer(msg.sender, seizeAmountWad);
    }

    function collateralValueUsdWad(address user) public view returns (uint256) {
        // valueUsdWad = amountWad * priceWad / 1e18
        return collateralOf[user] * oracle.priceWad() / WAD;
    }
}
```

---

### Step 2：写测试覆盖“边界 + 触发 + 清算后状态”

测试重点用例：
1. **刚好能借（==LTV 上限）**允许
2. **超过 1 wei** 立即 revert（锁边界）
3. **价格下跌触发清算**：找一个价格点让 `debt > colValue*LT`
4. **closeFactor 上限**：repay 超过上限 revert
5. **清算后断言**：债务减少、抵押减少、清算人抵押增加，且 seizeAmount 符合公式（含 bonus）

（示例测试代码略，建议使用你现有仓库的 `forge-std/Test.sol` 习惯组织；若你需要我可以按你仓库目录输出完整可跑版本。）

---

## 5. 关键公式“怎么来的”（通俗推导）

### 5.1 清算奖励公式：为什么 `seizeValue = repayValue * (1 + bonus)`？

清算人用自己的钱替你还债 `repayValue`，协议为了激励清算，允许他拿走比 repayValue 略多的抵押价值：

- `bonus=5%` → 倍率 `1.05`
- 因为链上无小数，用 WAD 表示：`1.05 = (WAD + bonusWad) / WAD`

因此：
- `seizeValueUsdWad = repayWad * (WAD + bonusWad) / WAD`

### 5.2 为什么 `seizeAmount = seizeValue * WAD / price`？

因为：
- `seizeValueUsdWad` 是“美元价值（WAD）”
- `priceUsdPerColWad` 是“每 1 COL 的美元价格（WAD）”
- 直接做 `seizeValue / price` 会丢精度（整数除法）
- 所以先乘 `WAD` 再除：`seizeAmountWad = seizeValueUsdWad * WAD / priceUsdPerColWad`

---

## 6. 本次提问 Q&A（收录）

### Q1：为什么要清算人还债，不是谁借的谁还吗？
A：因为借款人可能不愿还或无力还，协议不能干等导致坏账。清算机制允许第三方替借款人还债，快速把风险仓位拉回安全区。

### Q2：那我需要还清算人的钱吗？
A：一般不需要。清算是“repay 换 seize”的即时交换，你付出的代价是抵押被扣走（含 bonus），不会再欠清算人一笔钱。

### Q3：这种时候抵押品还值钱吗？
A：抵押品仍有市场价值，否则清算人也不会来清算。触发清算的原因是“相对债务而言不够安全”（debt > colValue*LT），而不是抵押品没价值。

### Q4：为什么还要除 WAD，单位换算怎么理解？
A：两个 18 位精度数相乘会多出一个 1e18，想让结果仍是 18 位，就要除一次 1e18。通用模板见第 2 节。

### Q5：清算奖励公式怎么来的？
A：清算人替你还 `repay`，协议给 `bonus`，所以应得价值 = repay×(1+bonus)。链上用 WAD 表示倍率：`(WAD + bonusWad)/WAD`。

### Q6：如何使用 emit log 或在合约中打印中间值？
A：
- **测试里打印（推荐）**：`emit log_named_uint("x", x);`（需要继承 `Test`）
- **合约里打印（开发期推荐）**：`import "forge-std/console2.sol"; console2.log("x", x);`
- **合约里通用做法**：自定义 `event Debug(...)`，在关键点 `emit Debug(...)`，通过交易日志查看。

---

## 7. 调试技巧：定位“单位/边界”错误

在测试里打印这些最有效：
- `collateralAmountWad`、`priceWad`、`collateralValueUsdWad`
- `debtWad`
- `maxDebtUsdWad = colValue*LTV/WAD`
- `thresholdUsdWad = colValue*LT/WAD`
- 清算计算：`seizeValueUsdWad`、`seizeAmountWad`

运行：
- `forge test -vvv --match-test <testName>`

---

## 8. 分支与 Commit 信息（建议）

- 分支名：`d52-lending-collateral-boundary-liquidation`
- Commit（建议拆两次更清晰）：
  1. `feat(d52): add minimal lending with ltv/lt and liquidation`
  2. `test(d52): cover collateral boundary and liquidation trigger cases`
