# Signature Security Lab（签名专项漏洞与防护 · Foundry）

> 作品集级签名专项仓库：用 Foundry 构建“可跑的 PoC + 回归测试 + 审计清单”。
>
> 覆盖：EIP-191 / EIP-712、nonce 重放、deadline、domain separation（chainId/contract address）、EIP-2612 Permit、以及（可扩展）跨链/跨 App 消息重放。

---

## 🧭 Navigation（入口导航）

- 📚 学习索引（按月份）：`docs/2026/INDEX.md`
- 🧪 Foundry 子工程（核心代码/测试）：`labs/foundry-labs/`
  - 子工程说明：`labs/foundry-labs/README.md`
- 🧾 测试点清单（通用 checklist）：`docs/checklists/test-points.md`
- 🧰 Foundry cheatcodes 速查：`docs/cheatsheets/foundry-cheatcodes.md`
- 📊 覆盖率说明：`docs/reports/coverage.md`
- 🧷 一键脚本：`scripts/`（bootstrap/test/coverage/fmt）

---

## 🎯 Threat Model（威胁模型）

签名体系的风险本质：**签名是“离线授权凭证”**。一旦泄露/被钓鱼拿到，就要假设攻击者能无限次、在任意时刻提交到链上。

### 攻击者能力假设
- 能拿到用户签名（钓鱼、前端注入、日志泄露、被动抓包、截图、社工）
- 能重复提交同一份签名（**重放**）
- 能在不同合约、不同链、不同业务域之间复用签名（**跨域重放**）
- 能利用 MEV 夹击（front-run/back-run）放大授权类风险
- 能利用时间戳的有限偏移卡边界（deadline）

### 保护目标（Assets）
- 资产：token / vault / NFT
- 授权：approve / permit / role / meta-tx
- 跨域消息：messageId 唯一性与“只能执行一次”

### 常见失败模式（Failure Modes）
- ❌ 未引入 nonce / 未消耗 nonce → 同签名可反复执行
- ❌ 未校验 deadline → 永不过期签名
- ❌ domain separation 缺字段 → 换链/换合约仍可用
- ❌ 使用 `abi.encodePacked` 组 hash → 碰撞/类型混淆
- ❌ EIP-191 / EIP-712 前缀或域组装错误 → “验了，但验错了”
- ❌ permit nonce / allowance 更新不正确 → 可重放/可绕过

---

## ✅ Use-case Matrix（用例矩阵：风险 → 测试断言 → 修复）

| Category | Risk | What to Assert（测试断言） | Expected Fix（修复方式） |
|---|---|---|---|
| Nonce | 同签名重放 | 同一签名提交两次：第二次必须 revert；余额/总量/状态不变 | `nonce++` 或 `used[hash]=true` |
| Deadline | 永不过期 / 卡边界 | `deadline < block.timestamp` 必须 revert；边界（=`==`）明确 | 校验 deadline；明确 `<`/`<=` |
| Domain Separation | 跨链/跨合约重放 | 换 chainId / verifyingContract：签名必须失效 | EIP-712 domain 绑定 chainId+合约地址 |
| Message Binding | 跨业务域复用 | 同 payload 换业务字段（type/srcApp/dstApp）应无效 | messageId 纳入业务域字段 |
| Encoding | hash 碰撞 | 演示 packed 碰撞；修复后碰撞失效 | 用 `abi.encode` + typehash |
| EIP-191 | 前缀不一致 | 错误前缀导致“验错消息”；正确前缀才能通过 | 使用标准库/一致前缀 |
| EIP-712 | typed data 结构错误 | typehash/structHash/domain 一致；字段顺序类型一致 | 严格按 EIP-712 组装 |
| EIP-2612 Permit | nonce/allowance 错误 | permit 后 allowance 生效、nonce 递增、deadline 生效、重放失败 | OZ `ERC20Permit` 或正确实现 |

> 你可以把 D37/D38/D39/D41 的用例逐步补齐到矩阵里，矩阵就是“作品集的目录”。

---

## 📁 Repo Layout（与你当前结构一致）

```
.
├── README.md                       # (本文件) 作品集入口
├── docs/
│   ├── 2026/
│   │   ├── 01/
│   │   ├── 02/
│   │   └── INDEX.md                # 月度索引入口
│   ├── cheatsheets/foundry-cheatcodes.md
│   ├── checklists/test-points.md
│   └── reports/coverage.md
├── labs/
│   └── foundry-labs/               # Foundry 子工程（核心代码与测试）
│       ├── README.md
│       ├── foundry.toml
│       ├── src/
│       └── test/
└── scripts/
    ├── bootstrap.sh
    ├── test.sh
    ├── coverage.sh
    └── fmt.sh
```

---

## 🚀 Quickstart（推荐使用 scripts）

### 1) 初始化依赖
```bash
./scripts/bootstrap.sh
```

### 2) 跑测试
```bash
./scripts/test.sh
```

### 3) 生成覆盖率（如果你 coverage.sh 已配置）
```bash
./scripts/coverage.sh
```

### 4) 格式化
```bash
./scripts/fmt.sh
```

---

## 🧪 常用 Foundry 命令（进入子工程）

```bash
cd labs/foundry-labs
forge build
forge test -vvv
```

如需按主题过滤（示例，按你的实际命名调整）：
```bash
forge test --match-path test/vulns/D3*.t.sol -vvv
forge test --match-contract D39_Permit_Test -vvv
```

---

## 🔍 Audit Checklist（签名专项审计清单 · 快速版）

### Nonce / Replay
- [ ] 签名是否“一次性”（nonce 递增或 used 标记）？
- [ ] 是否存在任何路径允许重放成功？
- [ ] revert 是否明确（自定义 error / 清晰信息）？

### Deadline / Time window
- [ ] 是否校验 deadline？比较符号 `<`/`<=` 是否符合设计？
- [ ] 是否存在永不过期签名？
- [ ] 是否有边界测试（最后一秒、过期一秒）？

### Domain separation（EIP-712）
- [ ] domain 是否包含 `chainId` + `verifyingContract`？
- [ ] 换链/换合约后，签名是否必然失效？

### Encoding / Hashing
- [ ] 避免 `abi.encodePacked` 的碰撞风险（结构化 hash 用 `abi.encode`）
- [ ] typehash / structHash 字段顺序类型完全一致

### Permit（EIP-2612）
- [ ] nonce 递增
- [ ] allowance 写入正确（owner->spender）
- [ ] deadline 生效
- [ ] 重放失败（同签名第二次 revert）

---

## 📌 Status（按你的 Dxx 逐步补全）

- D37 nonce replay ✅
- D38 domain separation ✅
- D39 EIP-2612 permit ✅
- D41 作品级 README（本文件）✅

> 详细学习文档请见：`docs/2026/INDEX.md`（按月索引进入每日 Dxx）
