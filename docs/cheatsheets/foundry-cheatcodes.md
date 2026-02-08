# Foundry Cheatcodes 速查表（一页版）

> 适用：`forge-std/Test.sol`，通过 `vm` 调用（`Vm` cheatcodes）。  
> 目标：写测试时快速查“怎么改 msg.sender / 断言 revert / 控制时间 / 做 fuzz / 打日志”。

---

## 0) 最小测试模板
```solidity
import "forge-std/Test.sol";

contract XTest is Test {
    address alice = address(0xA11CE);
    function setUp() public {}
    function test_example() public { assertTrue(true); }
}
```

---

## 1) 身份/权限：msg.sender / tx.origin

### `vm.prank(addr)`：只影响下一次调用
```solidity
vm.prank(alice);
token.transfer(bob, 1);
```

### `vm.startPrank(addr)` + `vm.stopPrank()`：影响一段调用
```solidity
vm.startPrank(alice);
token.approve(spender, 100);
token.transfer(bob, 1);
vm.stopPrank();
```

### `vm.prank(sender, origin)`：同时设置 msg.sender + tx.origin
```solidity
vm.prank(alice, alice);
```

---

## 2) 断言 revert：异常分支必备

### `vm.expectRevert()`：只要 revert 就算通过
```solidity
vm.expectRevert();
token.transfer(bob, 1e18);
```

### `vm.expectRevert(bytes)`：精确匹配 revert 数据（推荐）

**自定义 error**
```solidity
vm.expectRevert(abi.encodeWithSelector(MyErr.selector, alice));
foo.bar();
```

**require("msg")（字符串）**
```solidity
vm.expectRevert(bytes("NOT_OWNER"));
foo.onlyOwner();
```

> 习惯：`expectRevert` 必须写在“会 revert 的那一次调用之前”。

---

## 3) 事件断言：expectEmit
```solidity
vm.expectEmit(true, true, false, true);
emit Transfer(alice, bob, 1);
vm.prank(alice);
token.transfer(bob, 1);
```

参数含义（从左到右）：
- topic1 / topic2 / topic3 / data 是否参与匹配

> 常见坑：你要先 `emit` 一次“期望事件”，再执行真实调用。

---

## 4) 时间/区块：warp / roll / skip

### `vm.warp(ts)`：改 block.timestamp
```solidity
vm.warp(block.timestamp + 1 days);
```

### `vm.roll(blockNumber)`：改 block.number
```solidity
vm.roll(block.number + 100);
```

### `skip(seconds)`：forge-std 提供的便捷方法（内部就是 warp）
```solidity
skip(1 days);
```

---

## 5) 余额/资金：deal / hoax

### `deal(token, to, amount)`：直接改 ERC20 余额（测试神器）
```solidity
deal(address(token), alice, 100 ether);
```

### `vm.deal(addr, eth)`：直接改 ETH 余额
```solidity
vm.deal(alice, 10 ether);
```

### `hoax(addr, eth)`：给地址充 ETH + prank（下一次调用）
```solidity
hoax(alice, 1 ether);
payable(target).call{value: 0.1 ether}("");
```

---

## 6) 调用外部/模拟返回：mockCall / expectCall

### `vm.mockCall(target, calldata, returndata)`
```solidity
bytes memory cd = abi.encodeWithSelector(Oracle.getPrice.selector);
vm.mockCall(address(oracle), cd, abi.encode(uint256(123)));
assertEq(oracle.getPrice(), 123);
```

### `vm.expectCall(target, calldata)`：断言某次调用发生
```solidity
vm.expectCall(address(oracle), abi.encodeWithSelector(Oracle.getPrice.selector));
foo.doSomething();
```

---

## 7) 存储/低级能力：load / store（慎用，但很强）
```solidity
bytes32 slot0 = vm.load(addr, bytes32(uint256(0)));
vm.store(addr, bytes32(uint256(0)), bytes32(uint256(1)));
```

> 常用于：绕过复杂初始化、验证存储布局、快速构造状态。作品集里建议只在“解释清楚的场景”用。

---

## 8) 选择性执行：assume / bound（Fuzz 常用）

### `vm.assume(cond)`：过滤不合法输入
```solidity
vm.assume(x > 0 && x < 1e18);
```

### `bound(x, min, max)`：把 fuzz 输入收敛到范围
```solidity
x = bound(x, 1, 1e18);
```

---

## 9) 角色/地址工具：makeAddr / label

### `makeAddr("alice")`：生成稳定地址（更可读）
```solidity
address alice = makeAddr("alice");
```

### `vm.label(addr, "ALICE")`：为地址打标签（debug 更爽）
```solidity
vm.label(alice, "ALICE");
```

---

## 10) 日志调试：emit log_* / console2

### `emit log_*`（forge-std）
```solidity
emit log_named_uint("bal", token.balanceOf(alice));
```

### `console2.log`（更像 JS console）
```solidity
import "forge-std/console2.sol";
console2.log("bal", token.balanceOf(alice));
```

---

## 11) Fork（可选进阶）：createSelectFork / selectFork
> 如果你 D15/D16 做 fork 案例会用到。
```solidity
uint256 forkId = vm.createSelectFork(RPC_URL, 19_000_000);
vm.selectFork(forkId);
```

---

## 12) 常用组合（记这 5 个就够你写 80% 测试）
- 身份：`prank / startPrank`
- 异常：`expectRevert`
- 事件：`expectEmit`
- Fuzz：`assume / bound`
- 时间：`warp / skip`

---

## 常见坑速记
- `expectRevert/expectEmit/expectCall`：**必须写在触发行为之前**
- `transferFrom/safeTransferFrom`：身份要对（`prank` 让 msg.sender 正确）
- fuzz 失败经常是：没 `bound/assume`，输入空间太大导致溢出/无意义 revert

---

## 可选：配套示例测试建议
建议写一个 `test/Cheatcodes.t.sol`，每类 cheatcode 1 个最小用例，跑通就是最好的“速查表验证”。
