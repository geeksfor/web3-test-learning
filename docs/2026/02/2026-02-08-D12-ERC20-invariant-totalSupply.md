# 2026-02-08 - D12 | Foundry Invariant 入门：ERC20 `totalSupply == minted - burned`（ghost state / Handler）

tags: [foundry, forge, solidity, testing, invariant, fuzz, erc20]

## 背景 / 目标

今天目标是跑通 Foundry 的 **invariant（不变量）测试**，并用一个最经典的性质来约束 ERC20 的铸造/销毁逻辑：

- **Invariant**：`totalSupply == mintedSum - burnedSum`  
  - `mintedSum`：所有成功 mint 的总量（ghost state）
  - `burnedSum`：所有成功 burn 的总量（ghost state）

同时学习如何用 trace 定位失败点，并理解“为什么 invariant 能抓到 bug”。


## 你会得到什么（今日完成清单）

- ✅ 写出 `Handler`（暴露给 invariant 引擎随机调用的入口函数集合）
- ✅ 学会 `targetContract / targetSelector`
- ✅ 用 ghost state 统计 `mintedSum / burnedSum`
- ✅ 写出 invariant：`totalSupply == mintedSum - burnedSum`
- ✅ 通过 trace 精准定位错误（示例：`mint()` 没更新 `totalSupply`）


## 核心概念速记

### 1) Invariant 测试是什么？

Invariant 的思路不是“写一个确定的输入 -> 断言输出”，而是：

> 让引擎随机调用一堆操作（mint/burn/transfer/approve…），并在任意时刻都必须满足某个永真条件（不变量）。

因此它非常适合抓：
- supply/balance/allowance 维护不一致
- 特殊路径漏更新状态
- 某些操作组合后出现 underflow/overflow（在旧版本或 unchecked 场景）


### 2) Handler（操作集合）是什么？

Invariant 引擎不会直接随机调用你的 token 合约（那样太乱），我们通常写一个 **Handler 合约**：

- 里面有 `mint/burn/burnFrom/transfer` 等函数
- 引擎随机调用这些函数
- Handler 内部用 `vm.prank(...)` 模拟不同的 `msg.sender`
- Handler 内部维护 ghost state（影子账本）用于 invariant 对比


### 3) Ghost State（影子账本）是什么？

合约本身通常不会提供 `mintedTotal/burnedTotal` 统计变量。  
测试里我们用 handler 记录：

- `mintedSum += amount`
- `burnedSum += amount`

最后 invariant 里对比：

- `token.totalSupply() == mintedSum - burnedSum`


## 代码：D12 Invariant 测试（可直接复制跑通）

建议新增文件：

- `labs/foundry-labs/test/erc20/SimpleERC20.invariant.t.sol`

> 说明：为了让 invariant 通过，mint 建议调用 `mintOnlyOwner()`（它会走 `_mint` 更新 totalSupply）。  
> 如果你在 handler 中调用了你合约里那个 **不更新 totalSupply 的 `mint()`**，invariant 会立刻失败（这正是我们想体验的）。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../src/SimpleERC20.sol";

contract ERC20Handler is Test {
    SimpleERC20 public token;
    address public owner;

    // 地址池（固定几个人，避免随机地址带来不可控情况）
    address[] public users;

    // ghost state
    uint256 public mintedSum;
    uint256 public burnedSum;

    constructor(SimpleERC20 _token, address _owner) {
        token = _token;
        owner = _owner;

        users.push(address(0xA11CE));
        users.push(address(0xB0B));
        users.push(address(0xCAro1));
        users.push(address(0xDAVE));
    }

    function _pickUser(uint256 seed) internal view returns (address) {
        return users[seed % users.length];
    }

    // 1) mint：用 mintOnlyOwner（会更新 totalSupply）
    function mint(uint256 toSeed, uint256 amount) external {
        address to = _pickUser(toSeed);
        amount = bound(amount, 0, 1e24); // 控制规模，避免跑得慢/溢出风险

        vm.prank(owner);
        token.mintOnlyOwner(to, amount);

        mintedSum += amount;
    }

    // 2) burn：burn 自己（amount 必须 <= balance）
    function burn(uint256 whoSeed, uint256 amount) external {
        address who = _pickUser(whoSeed);
        uint256 bal = token.balanceOf(who);
        if (bal == 0) return;

        amount = bound(amount, 0, bal);

        vm.prank(who);
        token.burn(amount);

        burnedSum += amount;
    }

    // 3) burnFrom：spender burn tokenOwner（需要 allowance + balance）
    function burnFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address tokenOwner = _pickUser(ownerSeed);
        address spender = _pickUser(spenderSeed);
        if (tokenOwner == spender) return;

        uint256 bal = token.balanceOf(tokenOwner);
        if (bal == 0) return;

        // 给 spender 授权（随机授一个 <= bal 的额度）
        uint256 approveAmt = bound(amount, 0, bal);
        vm.prank(tokenOwner);
        token.approve(spender, approveAmt);

        if (approveAmt == 0) return;

        // burnFrom 的 amount 不能超过 allowance & balance
        uint256 allowed = token.allowance(tokenOwner, spender);
        uint256 maxBurn = bal < allowed ? bal : allowed;
        if (maxBurn == 0) return;

        uint256 burnAmt = bound(amount, 0, maxBurn);

        vm.prank(spender);
        token.burnFrom(tokenOwner, burnAmt);

        burnedSum += burnAmt;
    }

    // 4) transfer：不影响 supply，但有助于打乱余额分布
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _pickUser(fromSeed);
        address to = _pickUser(toSeed);
        if (from == to) return;

        uint256 bal = token.balanceOf(from);
        if (bal == 0) return;

        amount = bound(amount, 0, bal);

        vm.prank(from);
        token.transfer(to, amount);
    }
}

contract SimpleERC20InvariantTest is StdInvariant, Test {
    SimpleERC20 token;
    ERC20Handler handler;

    address owner = address(this);

    function setUp() public {
        token = new SimpleERC20();
        handler = new ERC20Handler(token, owner);

        targetContract(address(handler));

        // （可选）限制只调用指定函数，减少噪声
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = ERC20Handler.mint.selector;
        selectors[1] = ERC20Handler.burn.selector;
        selectors[2] = ERC20Handler.burnFrom.selector;
        selectors[3] = ERC20Handler.transfer.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // Invariant 1：totalSupply 必须等于 minted-burned
    function invariant_totalSupply_matches_minted_minus_burned() public view {
        assertEq(token.totalSupply(), handler.mintedSum() - handler.burnedSum());
    }

    // Invariant 2：burnedSum 永远不可能超过 mintedSum
    function invariant_burned_le_minted() public view {
        assertLe(handler.burnedSum(), handler.mintedSum());
    }
}
```


## 运行方式

在 `labs/foundry-labs` 目录下：

```bash
forge test --match-contract SimpleERC20InvariantTest -vvv
```

加大随机次数：

```bash
forge test --match-contract SimpleERC20InvariantTest -vvv --runs 500
```


## 为什么 `owner = address(this)`？以及和 `vm.prank(who)` 的关系

- `SimpleERC20` 构造函数里 `owner = msg.sender`
- 在 `setUp()` 中 `token = new SimpleERC20()` 是由测试合约部署的
- 因此部署时的 `msg.sender` 就是测试合约地址：`address(this)`
- 所以 `token.owner()` 也等于 `address(this)`

`vm.prank(x)` 只会影响 **下一次外部调用** 的 `msg.sender`：

- `vm.prank(owner); token.mintOnlyOwner(...)` ✅ 通过 onlyOwner
- `vm.prank(who); token.burn(...)` ✅ burn 自己余额（不需要 onlyOwner）


## 如何读 trace：定位 invariant 为什么失败（用你的失败案例）

你贴的失败日志核心部分：

- `totalSupply() -> 0`
- `mintedSum() -> 3013...`
- `burnedSum() -> 0`
- `assertEq(0, 3013...)` 失败

并且最小复现序列被 shrink 到 1 步：

- 只调用了一次 `ERC20Handler::mint(...)` 就能导致 invariant 失败

在 trace 里还能看到它实际调用的是：

- `SimpleERC20::mint(to, amount)`（注意：不是 `mintOnlyOwner`）

而你合约当前 `mint()` 的实现是：

```solidity
function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
    emit Transfer(address(0), to, amount);
}
```

它 **没有** `totalSupply += amount`，所以：

- handler 的 ghost state 记了 mintedSum 增加
- token.totalSupply 仍然是 0
- invariant 立刻失败 ✅（成功抓到 bug）


## 修复建议（让 invariant 通过）

你有两种常见修法（二选一即可）：

### 修法 A：修复 `mint()`，让它走 `_mint()`

```solidity
function mint(address to, uint256 amount) external {
    _mint(to, amount);
}
```

### 修法 B：移除/禁用无权限 mint，只保留 `mintOnlyOwner()`

对于真实 ERC20，这通常更安全：避免任何人无限增发。


## 常见坑位 Checklist

- [ ] handler 的 mint 是否走了会更新 `totalSupply` 的入口（`_mint / mintOnlyOwner`）
- [ ] burn/burnFrom 是否 bound 到余额/allowance（否则大量 revert 影响信噪比）
- [ ] amount 是否 bound 到合理范围（避免跑太慢或溢出）
- [ ] 用 `targetSelector` 限制 selector（初学强烈建议）
- [ ] invariant 失败时先看：失败的断言 + shrink 后的最小序列


## 今日总结

- invariant 的价值：用“永真条件”约束复杂随机序列中的状态一致性
- handler + ghost state：让你能测到合约原本没暴露的统计逻辑
- trace + shrink：Foundry 会给出最小复现序列，定位 bug 极快
- 你这次的失败是一个经典案例：**Transfer 事件像铸币，但 totalSupply 没更新**，invariant 秒抓
