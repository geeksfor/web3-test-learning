# 2026-02-12 - D17（进阶）Proxy / delegatecall / UUPS onlyProxy（贴近生产）

tags: [solidity, security, upgradeable, proxy, delegatecall, uups, openzeppelin, foundry, audit]

本文整理了今天围绕 **Proxy 原理、delegatecall、初始化窗口期、UUPS onlyProxy、OpenZeppelin 5.5 行为变化** 的学习内容，以及你在实现/测试过程中提出的关键疑问与结论（含踩坑记录与修复方案）。

---

## 今日目标
1. 彻底理解 **Proxy + delegatecall**：代码在哪里跑？storage 写到哪里？
2. 理解并实践：initialize 重复调用、Proxy 初始化窗口期、UUPS onlyProxy
3. 用 **OpenZeppelin 5.5** 对齐生产：理解为何窗口期在 OZ 5.5 下会被框架拦截，以及审计/面试如何表述。

---

## 一、Proxy 原理与 delegatecall：最重要的心智模型

### 1) Proxy / Impl 的分工
- **Proxy**：对外地址固定；**状态（storage）在 Proxy**
- **Impl**：放业务逻辑代码；可替换（升级=换 impl 地址）

一句话：**Proxy 存数据，Impl 提供功能。**

### 2) delegatecall 的语义（决定一切）
`delegatecall`：执行 Impl 的代码，但使用 **当前合约（Proxy）** 的上下文，因此：
- 写 storage：写 **Proxy 的 storage**
- `address(this)`：在 Impl 代码中看到的是 **Proxy 地址**
- `msg.sender`：保持外部调用者（不是 Proxy）

这解释了：
- constructor 初始化 Impl 自己的 storage，对 Proxy 无效
- 初始化必须放到 `initialize()` 并通过 Proxy delegatecall 执行

---

## 二、你问到的关键点与答案汇总（Q&A）

### Q1：`vm.deal(address(this), 10 ether)` 为什么还要 `address(bad).call{value: 5 ether}("")`？
A：`address(this)` 是测试合约地址，`address(bad)` 是被测合约地址，不同地址。
- `vm.deal(address(this), 10 ether)`：给测试合约“发钱”
- `address(bad).call{value: 5 ether}("")`：把钱真正转入 bad 合约（才能演示 sweep/盗取）

### Q2：`abi.encodeCall(MinimalImpl.initialize, (alice))` 是什么意思？initData 包含什么？
A：把 `initialize(alice)` 编码成 calldata：
- 前 4 字节：selector = keccak256("initialize(address)")[:4]
- 后面：参数 ABI 编码（32 字节对齐，address 左补 0）
用于 Proxy 构造时 `delegatecall(initData)` 原子初始化。

### Q3：`impl.delegatecall(initData)` 后，`initialized=true`、`owner=_owner` 存到哪里？
A：存到 **Proxy**。delegatecall 让 Impl 的 `SSTORE` 写到当前合约（Proxy）storage。

### Q4：Proxy 里没声明 `owner/initialized`，为什么还能写？
A：EVM storage 是 slot→value 表，不依赖源码声明。Impl 编译后对变量的读写是对固定 slot 的 `SLOAD/SSTORE`；delegatecall 让这些 slot 写到 Proxy 上。

### Q5：Proxy 与 Impl 不同地址，为什么会“变量布局冲突（storage collision）”？
A：冲突发生在 **Proxy 的 storage 内部**：Impl 的 slot0/1… 也写 Proxy 的 slot0/1…
若 Proxy 用普通变量把 implementation/admin 放 slot0/1，就可能被 Impl 的 owner/number 覆盖。
因此 Proxy 用 **EIP-1967 的超大固定 slot** 存 implementation/admin，避免与 Impl 常规 slot0/1/2 冲突。

### Q6：`assembly { sstore(slot, a) }` 是什么？
A：Solidity 内联汇编（Yul），直接执行 EVM `SSTORE`：`storage[slot] = a`。用于把 Proxy 管理数据写入 EIP-1967 固定 slot。

### Q7：为什么 `constructor(){ _disableInitializers(); }` 会导致第一次 initialize 就失败？
A：因为你直接对 **实现合约地址（Impl）** 调 initialize 了；_disableInitializers() 会锁死 Impl 自身初始化版本号。
生产正确姿势：Impl 锁死；初始化发生在 **Proxy 上**（delegatecall 写 Proxy storage）。

### Q8：`upgradeToAndCall` 是什么函数？我没写它
A：它来自父类 **UUPSUpgradeable**。含义：升级 implementation，并可选立刻 delegatecall 一段 data 做升级后初始化（如 initializeV2）。

### Q9：`__UUPSUpgradeable_init()` 为什么报未声明？
A：你当前 OZ 5.x 版本里可能没有/不需要该 init。结论：删除即可，不影响 onlyProxy 行为。

### Q10：为什么提示合约应标记 abstract？
A：通常是 `_authorizeUpgrade(address)` 没有正确 override（签名不匹配）。建议写：
`function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}`

---

## 三、OZ 5.5 的关键变化：`ERC1967ProxyUninitialized()`
你尝试 `new ERC1967Proxy(impl, "")` 时 OZ 5.5 直接 revert：`ERC1967ProxyUninitialized()`。
含义：OZ 5.5 强制 Proxy 部署时必须原子初始化（initData 非空），从框架层面避免未初始化窗口期。

审计/面试表述建议：
- 经典风险存在（未初始化 proxy 可被抢初始化夺权）
- 但使用 OZ 5.5 ERC1967Proxy 时，构造阶段强制 initData，默认规避该风险
- 审计仍需检查项目是否确实使用该实现与版本、部署脚本是否传 initData、是否存在其他代理/自研 proxy 绕过门禁

---

## 四、UUPS onlyProxy：为什么升级入口必须走 Proxy
- 直接对 impl 地址调用升级函数属于错误上下文：应当 revert（onlyProxy）
- 通过 Proxy 调用升级函数（delegatecall 上下文）才能写到 Proxy 的 EIP-1967 implementation slot 并完成升级
- 升级权限由 `_authorizeUpgrade` 统一控制（owner/multisig/timelock）

---

## 五、remappings 踩坑：`@openzeppelin/=` 与 upgradeable 冲突
你遇到的冲突：
- `@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/`
- `@openzeppelin/=lib/openzeppelin-contracts/`

后者太宽，会截胡 `@openzeppelin/contracts-upgradeable/...`，导致路径拼成 `lib/openzeppelin-contracts/contracts-upgradeable/...`（不存在）。

推荐 remappings（精确两条）：
- `@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/`
- `@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/`

---

## 六、审计视角 Checklist（贴近生产）

### 初始化（Initialization）
- [ ] 是否存在 initialize/init/setup/config 入口可改关键状态？
- [ ] 是否有一次性锁（initializer / 版本锁）？是否可重复 init 覆盖 owner/admin/roles/treasury 等？
- [ ] 是否校验 address(0)，是否存在锁逻辑写错/漏写回？

### 部署/升级流程（Atomic init & Window）
- [ ] Proxy 部署是否原子初始化（构造参数 initData）？
- [ ] 非 OZ 5.5 / 自研 proxy 是否存在未初始化窗口期？
- [ ] 工厂批量部署/CREATE2 场景是否后置初始化？

### 实现合约自身安全（Impl hardening）
- [ ] impl 是否 `_disableInitializers()` 防止 impl 地址被 initialize？
- [ ] 是否存在资产误转到 impl 的风险 + sweep/rescue 等敏感函数？

### UUPS
- [ ] onlyProxy/notDelegated 是否生效（直接在 impl 上调用升级函数应失败）？
- [ ] `_authorizeUpgrade` 权限是否足够强？
- [ ] 升级新增变量是否 `reinitializer(n)` 并在升级后立刻执行？

---

## 今日结论
1) delegatecall = 用 Impl 代码，写 Proxy storage  
2) storage collision 是 Proxy 自己的 slot 冲突：Impl 的 slot0/1…落在 Proxy 上  
3) EIP-1967 用超大固定 slot 保存 admin/implementation 避免冲突  
4) OZ 5.5 默认强制原子初始化，直接避免“未初始化窗口期”  
5) UUPS 升级必须 onlyProxy，权限由 `_authorizeUpgrade` 控制  
6) remappings 用精确映射，避免宽映射截胡 upgradeable 包
