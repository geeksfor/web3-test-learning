# 2026-02-06 - D11 | 权限模型：Ownable / AccessControl（错误示例 vs 正确示例）+ Foundry 测试

tags: [foundry, solidity, openzeppelin, access-control, ownable, testing, security]

## 背景 / 目标
今天目标是把 **两种最常见权限模型**（Ownable / AccessControl）用「**错误示例 + 正确示例**」跑通，并用 Foundry 测试**证明漏洞存在/被修复**。

你今天最终要得到：
- ✅ Ownable：**Bad（漏 onlyOwner）** vs **Good（onlyOwner）**
- ✅ AccessControl：**Good（DEFAULT_ADMIN 管理 MINTER）**
- ✅ AccessControl 三大典型坑（Bad）：
  1) **未初始化 MINTER_ROLE**（功能永久不可用）
  2) **role admin 配成不可达角色**（治理锁死）
  3) **role self-admin**（越权扩张：minter 自己能发放 minter）

---

## 项目结构（建议）
```
src/auth/
  OwnableBadMint.sol
  OwnableGoodMint.sol
  AccessControlBadMint.sol
  AccessControlBadAdminLock.sol
  AccessControlBadSelfAdmin.sol
  AccessControlGoodMint.sol

test/auth/
  OwnableBadMint.t.sol
  OwnableGoodMint.t.sol
  AccessControlBadMint.t.sol
  AccessControlBadAdminLock.t.sol
  AccessControlBadSelfAdmin.t.sol
  AccessControlGoodMint.t.sol
```

---

## 环境准备（OpenZeppelin）
如果还没安装 OpenZeppelin：
```bash
cd labs/foundry-labs
forge install OpenZeppelin/openzeppelin-contracts --no-commit
```

`foundry.toml` 确保 remappings（很多项目已存在）：
```toml
remappings = [
  "@openzeppelin/=lib/openzeppelin-contracts/"
]
```

---

## Part A：Ownable

### A1. 错误示例（Bad）：忘记加 onlyOwner → 任何人都能 mint

**合约：`src/auth/OwnableBadMint.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract OwnableBadMint is Ownable {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    // ❌ 错误：没有 onlyOwner，任何人都能 mint 给任何人
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
```

**测试：`test/auth/OwnableBadMint.t.sol`（证明漏洞存在：攻击能成功）**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/auth/OwnableBadMint.sol";

contract OwnableBadMintTest is Test {
    OwnableBadMint token;

    address attacker = address(0xBEEF);

    function setUp() public {
        token = new OwnableBadMint();
        // owner 默认是部署者（本测试合约）
    }

    function test_Bad_anyoneCanMint() public {
        vm.prank(attacker);
        token.mint(attacker, 100);

        assertEq(token.balanceOf(attacker), 100);
        assertEq(token.totalSupply(), 100);
    }
}
```

> 重点：Bad case 的测试不是 expectRevert，而是**证明“越权成功”**。

---

### A2. 正确示例（Good）：mint 加 onlyOwner → 只有 owner 能 mint

**合约：`src/auth/OwnableGoodMint.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract OwnableGoodMint is Ownable {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external onlyOwner {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
```

**测试：`test/auth/OwnableGoodMint.t.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/auth/OwnableGoodMint.sol";

contract OwnableGoodMintTest is Test {
    OwnableGoodMint token;

    address alice = address(0xA11CE);
    address attacker = address(0xBEEF);

    function setUp() public {
        token = new OwnableGoodMint();
    }

    function test_Good_ownerCanMint() public {
        token.mint(alice, 100);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.totalSupply(), 100);
    }

    function test_Good_nonOwnerCannotMint() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.mint(attacker, 1);
    }

    function test_Good_transferOwnership_changesAuthority() public {
        token.transferOwnership(alice);

        // 原 owner 不再能 mint
        vm.expectRevert();
        token.mint(alice, 1);

        // 新 owner alice 可以 mint
        vm.prank(alice);
        token.mint(alice, 10);
        assertEq(token.balanceOf(alice), 10);
    }
}
```

---

## Part B：AccessControl

### B0. 基础概念速记
- `DEFAULT_ADMIN_ROLE`：默认管理员角色，**可以 grant/revoke 其他角色**（取决于 role admin）
- `MINTER_ROLE`：业务角色（例如 mint 权限）
- `onlyRole(MINTER_ROLE)`：限制调用者必须拥有该角色
- `_setRoleAdmin(role, adminRole)`：设置 “role 的管理员角色是谁”
  - **坑点**：如果 adminRole 没人拥有，就会锁死；如果 adminRole=role 自己，就会扩张。

---

### B1. 错误示例（Bad #1）：忘记初始化 MINTER_ROLE → 永久不可用

**合约：`src/auth/AccessControlBadMint.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract AccessControlBadMint is AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor() {
        // ✅ 只设置了 admin，但 ❌ 没给任何人 MINTER_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
```

**测试：`test/auth/AccessControlBadMint.t.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/auth/AccessControlBadMint.sol";

contract AccessControlBadMintTest is Test {
    AccessControlBadMint token;
    address alice = address(0xA11CE);

    function setUp() public {
        token = new AccessControlBadMint();
    }

    function test_Bad_noOneCanMint_initially() public {
        vm.expectRevert();
        token.mint(alice, 100);
    }

    function test_Bad_adminCanGrant_thenMintWorks() public {
        token.grantRole(token.MINTER_ROLE(), address(this));
        token.mint(alice, 100);

        assertEq(token.balanceOf(alice), 100);
        assertEq(token.totalSupply(), 100);
    }
}
```

---

### B2. 错误示例（Bad #2）：role admin 配成“不可达角色” → 治理锁死

**合约：`src/auth/AccessControlBadAdminLock.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract AccessControlBadAdminLock is AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE"); // ❌ 没人拥有

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        // ❌ 错误：把 MINTER_ROLE 的管理员设为 GOVERNOR_ROLE，但没给任何人 GOVERNOR_ROLE
        _setRoleAdmin(MINTER_ROLE, GOVERNOR_ROLE);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
```

**测试：`test/auth/AccessControlBadAdminLock.t.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/auth/AccessControlBadAdminLock.sol";

contract AccessControlBadAdminLockTest is Test {
    AccessControlBadAdminLock token;

    address admin = address(0xADAD);
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    function setUp() public {
        token = new AccessControlBadAdminLock(admin);
    }

    function test_Bad_adminCannotGrantMinter_dueToWrongRoleAdmin() public {
        vm.prank(admin);
        vm.expectRevert();
        token.grantRole(token.MINTER_ROLE(), bob);
    }

    function test_Bad_noOneCanEverMint_ifNoMinterExists() public {
        vm.expectRevert();
        token.mint(alice, 1);
    }
}
```

---

### B3. 错误示例（Bad #3）：MINTER_ROLE 自管理（self-admin）→ 越权扩张

**合约：`src/auth/AccessControlBadSelfAdmin.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract AccessControlBadSelfAdmin is AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor(address admin, address initialMinter) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, initialMinter);

        // ❌ 致命：MINTER_ROLE 的管理员 = MINTER_ROLE 自己
        _setRoleAdmin(MINTER_ROLE, MINTER_ROLE);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
```

**测试：`test/auth/AccessControlBadSelfAdmin.t.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/auth/AccessControlBadSelfAdmin.sol";

contract AccessControlBadSelfAdminTest is Test {
    AccessControlBadSelfAdmin token;

    address admin  = address(0xADAD);
    address minter = address(0xB0B);
    address attacker = address(0xBEEF);
    address alice  = address(0xA11CE);

    function setUp() public {
        token = new AccessControlBadSelfAdmin(admin, minter);
    }

    function test_Bad_selfAdmin_allowsPrivilegePropagation() public {
        vm.prank(minter);
        token.mint(alice, 1);
        assertEq(token.balanceOf(alice), 1);

        vm.prank(minter);
        token.grantRole(token.MINTER_ROLE(), attacker);

        vm.prank(attacker);
        token.mint(attacker, 100);

        assertEq(token.balanceOf(attacker), 100);
        assertEq(token.totalSupply(), 101);
    }
}
```

---

### B4. 正确示例（Good）：DEFAULT_ADMIN_ROLE 管理 MINTER_ROLE + 测试 grant/revoke

**合约：`src/auth/AccessControlGoodMint.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract AccessControlGoodMint is AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor(address admin, address initialMinter) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, initialMinter);
        // ✅ 不修改 role admin：MINTER_ROLE 默认由 DEFAULT_ADMIN_ROLE 管理
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
```

**测试：`test/auth/AccessControlGoodMint.t.sol`**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/auth/AccessControlGoodMint.sol";

contract AccessControlGoodMintTest is Test {
    AccessControlGoodMint token;

    address admin = address(0xADAD);
    address minter = address(0xB0B);
    address alice = address(0xA11CE);
    address attacker = address(0xBEEF);

    function setUp() public {
        token = new AccessControlGoodMint(admin, minter);
    }

    function test_Good_minterCanMint() public {
        vm.prank(minter);
        token.mint(alice, 100);

        assertEq(token.balanceOf(alice), 100);
        assertEq(token.totalSupply(), 100);
    }

    function test_Good_nonMinterCannotMint() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.mint(attacker, 1);
    }

    function test_Good_adminCanGrantAndRevokeMinter() public {
        vm.prank(admin);
        token.grantRole(token.MINTER_ROLE(), attacker);

        vm.prank(attacker);
        token.mint(attacker, 10);
        assertEq(token.balanceOf(attacker), 10);

        vm.prank(admin);
        token.revokeRole(token.MINTER_ROLE(), attacker);

        vm.prank(attacker);
        vm.expectRevert();
        token.mint(attacker, 1);
    }

    function test_Good_nonAdminCannotGrantRole() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.grantRole(token.MINTER_ROLE(), attacker);
    }
}
```

---

## 运行方式
跑全部 auth 测试：
```bash
forge test --match-path test/auth/*.t.sol -vvv
```

只跑 D11 的 AccessControl bad self-admin：
```bash
forge test --match-path test/auth/AccessControlBadSelfAdmin.t.sol -vvv
```

---

## 今日 Checklist（复习用）
### Ownable
- [ ] 关键敏感函数是否都加了 `onlyOwner`？
- [ ] 是否测试了 `transferOwnership` 后权限是否正确变化？

### AccessControl
- [ ] 业务角色（如 MINTER_ROLE）是否初始化（至少一个持有人）？
- [ ] role admin 配置是否正确（默认 admin 或治理角色确实有人持有）？
- [ ] 是否避免业务角色 self-admin（防止越权扩张）？
- [ ] 是否覆盖 `grantRole/revokeRole` 的正反用例（admin 能、非 admin 不能）？

---

## Commit 建议
- 分支：`d11-auth-ownable-accesscontrol`
- commit：
`feat(d11): add Ownable/AccessControl auth models with bad vs good tests`
