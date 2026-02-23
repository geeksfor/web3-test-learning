# D54：Vault share 小额存取款舍入（Rounding）边界回归（Foundry）

> 日期：2026-02-23  
> 关键词：ERC4626、Vault、share/asset 换算、整数除法舍入、donation 扭曲、边界测试、回归测试、审计断言

---

## 1. 这次任务要解决什么问题（通俗易懂）

Vault（也常对应 **ERC4626 Tokenized Vault**）会把用户存入的 **asset（底层资产）** 换成 **share（份额/凭证）**。  
份额代表你在金库里占比：share 越多，占比越大。

问题在于：Solidity 只有整数，没有小数，换算时一定会遇到 **除法取整（通常向下取整 floor）**。这会导致：

- 小额存入时：可能算出 `shares = 0`（但资产已经被转进 Vault）  
- 小额赎回时：可能算出 `assets = 0`（但 share 已被烧掉）  
- 在某些比例极端的情况下（例如有人直接给 Vault “捐赠”资产），小额操作会被“吞钱”或造成资金卡死，甚至被套利

D54 的目标就是：**写出能稳定复现这种 rounding 边界的测试**，并写出 **修复后的回归测试**（同样场景必须 revert 或被保护）。

---

## 2. 背后原理：为什么会发生 0 share / 0 asset

### 2.1 最常见的 share 换算公式（概念版）

当 Vault 已经有存量时，典型比例换算为：

- `shares = assets * totalSupply / totalAssets`
- `assets = shares * totalAssets / totalSupply`

其中：
- `totalAssets`：Vault 持有的底层资产数量（通常是 `asset.balanceOf(vault)`）
- `totalSupply`：share 的总供应量（所有人持有 share 之和）

### 2.2 整数除法向下取整是罪魁祸首

Solidity 的整数除法会向下取整：

- 真实值：`1 * 100 / 1_000 = 0.1`
- Solidity：`(1 * 100) / 1_000 = 0`

当比例极端时，小额 `assets` 乘上 `totalSupply` 仍然小于 `totalAssets`，就会出现 **shares = 0**。

### 2.3 donation（捐赠）如何把比例变“极端”

很多 Vault 的 `totalAssets()` 直接读取 `asset.balanceOf(address(this))`。  
如果有人 **不通过 deposit**，而是直接：

- `token.transfer(vault, X)` （直接打钱给 vault）

那么：

- `totalAssets` 增加了
- `totalSupply` 不变

结果：**每 1 share 对应的资产变多**，导致“新进来的人要存很多资产才换得到 1 share”。  
小额 deposit 就可能变成 `shares = 0`。

> 这也常被称作 donation attack / inflation attack 的一个触发条件（未必能直接获利，但可能造成他人损失或 DoS）。

---

## 3. 这次任务你能学到什么

1) **读懂 Vault/4626 的换算逻辑**：share/asset 的数学关系、比例随时变化  
2) **识别高风险点**：deposit/mint、withdraw/redeem 四条路径的 rounding 风险  
3) **会写“边界复现测试”**：小额、极端比例、donation 后的行为  
4) **会写“修复回归测试”**：修复点在哪里、断言应该怎么写（revert、状态不变、余额不被吞）  
5) **沉淀审计检查清单**：以后看任何 4626/Vault 都能快速扫出风险点

---

## 4. 实战实现步骤（Foundry）

### Step 0：准备文件

建议新增：

- `src/D54_VaultRounding.sol`
- `test/vulns/D54_VaultRounding.t.sol`

### Step 1：写“漏洞版”Vault

关键点：`deposit()` 里 **允许 `shares==0` 仍收走资产**（故意留洞）。

### Step 2：写“边界复现”测试

流程：

1. Alice 先存入一笔（建立 `totalSupply`）
2. Attacker 直接 donate 巨额 token 给 Vault（扭曲比例）
3. Bob 小额 deposit（例如 1 wei）  
   - 期望：Bob 资产减少，但 share 不增加（被吞）

### Step 3：修复

最低限度修复之一：

- `require(shares > 0)` 或自定义错误 `revert ZeroShares()`

更贴近真实产品的增强修复：

- deposit 增加用户保护参数：`minShares`
- redeem/withdraw 增加用户保护参数：`minAssetsOut`
- 使用 `mulDiv` 统一 rounding，避免溢出并控制向上/向下取整策略

### Step 4：写回归测试

复现同样场景：

- 修复后 Bob 小额 deposit 必须 revert（避免吞资产）
- 再补一条“正常比例下的小额 deposit 应该成功”，避免误伤正常用户

---

## 5. 参考代码（可直接复制）

### 5.1 合约：`src/D54_VaultRounding.sol`

> 包含：测试用 `SimpleERC20`、漏洞版 `VaultRoundingVuln`、修复版 `VaultRoundingFixed`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function mint(address, uint256) external;
}

contract SimpleERC20 is IERC20Like {
    string public name = "T";
    string public symbol = "T";
    uint8  public decimals = 18;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external override {
        balanceOf[to] += amount;
    }
}

abstract contract ShareLedger {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function _mint(address to, uint256 shares) internal {
        totalSupply += shares;
        balanceOf[to] += shares;
    }

    function _burn(address from, uint256 shares) internal {
        balanceOf[from] -= shares;
        totalSupply -= shares;
    }
}

contract VaultRoundingVuln is ShareLedger {
    IERC20Like public immutable asset;

    constructor(IERC20Like _asset) {
        asset = _asset;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply;
        uint256 assetsInVault = totalAssets();
        if (supply == 0 || assetsInVault == 0) return assets;
        return (assets * supply) / assetsInVault; // floor
    }

    // VULN: shares 可能为 0，但仍然 transferFrom 收走资产
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = _convertToShares(assets);
        require(asset.transferFrom(msg.sender, address(this), assets), "TF");
        if (shares > 0) _mint(receiver, shares);
    }
}

contract VaultRoundingFixed is ShareLedger {
    error ZeroShares();

    IERC20Like public immutable asset;

    constructor(IERC20Like _asset) {
        asset = _asset;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply;
        uint256 assetsInVault = totalAssets();
        if (supply == 0 || assetsInVault == 0) return assets;
        return (assets * supply) / assetsInVault; // floor
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = _convertToShares(assets);
        if (shares == 0) revert ZeroShares(); // ✅ 修复：避免吞资产
        require(asset.transferFrom(msg.sender, address(this), assets), "TF");
        _mint(receiver, shares);
    }
}
```

### 5.2 测试：`test/vulns/D54_VaultRounding.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SimpleERC20, VaultRoundingVuln, VaultRoundingFixed} from "../../src/D54_VaultRounding.sol";

contract D54_VaultRounding_Test is Test {
    SimpleERC20 token;
    VaultRoundingVuln  vuln;
    VaultRoundingFixed fixedVault;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address attacker = makeAddr("attacker");

    function setUp() public {
        token = new SimpleERC20();
        vuln = new VaultRoundingVuln(token);
        fixedVault = new VaultRoundingFixed(token);

        token.mint(alice, 100 ether);
        token.mint(bob, 10 ether);
        token.mint(attacker, 1_000_000 ether);

        vm.prank(alice);
        token.approve(address(vuln), type(uint256).max);
        vm.prank(alice);
        token.approve(address(fixedVault), type(uint256).max);

        vm.prank(bob);
        token.approve(address(vuln), type(uint256).max);
        vm.prank(bob);
        token.approve(address(fixedVault), type(uint256).max);
    }

    // 1) 漏洞复现：donation 后小额 deposit -> shares=0，但资产被吞
    function test_vuln_smallDeposit_afterDonation_mintsZeroShares_butTakesAssets() public {
        vm.prank(alice);
        vuln.deposit(100 ether, alice);
        assertEq(vuln.totalSupply(), 100 ether);

        vm.prank(attacker);
        token.transfer(address(vuln), 1_000_000 ether);

        uint256 bobAssetsBefore = token.balanceOf(bob);
        uint256 bobSharesBefore = vuln.balanceOf(bob);

        vm.prank(bob);
        vuln.deposit(1, bob);

        uint256 bobAssetsAfter = token.balanceOf(bob);
        uint256 bobSharesAfter = vuln.balanceOf(bob);

        assertEq(bobAssetsBefore - bobAssetsAfter, 1);
        assertEq(bobSharesAfter, bobSharesBefore);
    }

    // 2) 修复回归：同场景必须 revert（避免吞资产）
    function test_fixed_smallDeposit_afterDonation_revertsZeroShares() public {
        vm.prank(alice);
        fixedVault.deposit(100 ether, alice);

        vm.prank(attacker);
        token.transfer(address(fixedVault), 1_000_000 ether);

        vm.prank(bob);
        vm.expectRevert(VaultRoundingFixed.ZeroShares.selector);
        fixedVault.deposit(1, bob);
    }

    // 3) 额外回归：正常比例下小额 deposit 仍能成功（避免误伤）
    function test_fixed_smallDeposit_normalRatio_ok() public {
        vm.prank(alice);
        fixedVault.deposit(100 ether, alice);

        uint256 bobAssetsBefore = token.balanceOf(bob);

        vm.prank(bob);
        fixedVault.deposit(1 ether, bob);

        assertEq(token.balanceOf(bob), bobAssetsBefore - 1 ether);
        assertGt(fixedVault.balanceOf(bob), 0);
    }
}
```

---

## 6. 审计视角（Audit Checklist）

### 6.1 重点风险点（必须过一遍）

- [ ] `totalAssets()` 是否直接依赖 `asset.balanceOf(vault)`？若是，是否考虑 donation 扭曲比例？
- [ ] `deposit/mint` 是否可能出现 `shares == 0`？如果是：是否会“收资产但不给 share”？
- [ ] `withdraw/redeem` 是否可能出现 `assets == 0`？如果是：是否会“烧 share 但不给资产”？
- [ ] 换算是否使用 `mulDiv`/统一 rounding 策略？是否可能溢出？
- [ ] 是否提供用户保护参数：`minShares` / `minAssetsOut`（类似 AMM 的 minOut）？
- [ ] 是否具备边界回归测试：极小额、极端比例、donation 后、往返（deposit→redeem）不变量

### 6.2 推荐断言指标（测试里常用）

- 资产不应被“吞”：`assetsBefore - assetsAfter == depositAmount` 且 `sharesMinted > 0`  
- 修复后同样场景必须 revert：`expectRevert(ZeroShares)`  
- 状态不变量：`totalSupply` 与 `totalAssets` 的关系符合预期（例如：deposit 成功则 supply 增加）

---

## 7. 下一步可升级（可选）

如果你要把 D54 “升级一档”更贴近真实 ERC4626，可继续加：

- withdraw/redeem 的 `assets==0` 边界与回归
- `previewDeposit/previewRedeem` 与实际 `deposit/redeem` 一致性测试
- `mulDiv` + 指定 Rounding（Up/Down）的策略对照
- “小额循环套利”用例（利用 rounding 累积 1 wei 的利润）

---

## 8. 建议分支与提交信息

- 分支：`d54-vault-rounding-boundary`
- Commit message（Conventional Commit）：

`test(vault): add D54 rounding boundary + donation regression for shares`

