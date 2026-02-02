# 2026-02 学习索引（INDEX）

> 说明：本文件用于汇总 2026 年 02 月的每日学习文档，便于快速回顾与跳转。

## 目录

### 2026-02-01
- **D5 | Foundry Fuzz：随机 amount 的 transfer 后余额守恒（限制范围）+ VS Code 智能提示修复**  
  - 📄 文档：[`2026-02-01-D5-foundry-fuzz-transfer-balance-conservation.md`](./2026-02-01-D5-foundry-fuzz-transfer-balance-conservation.md)
  - 📦 代码：`labs/foundry-labs/src/SimpleERC20.sol`
  - 🧪 测试：`labs/foundry-labs/test/SimpleERC20.Fuzz.t.sol`  
  - 关键词：fuzz / bound / 余额守恒 / remappings.txt / IntelliSense
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --fuzz-runs 2000 --match-test testFuzz_transfer_balanceConservation -vvv
  ```

- **D5-2 | README + Coverage 初始盘点（待补覆盖率)**
- 📄 文档：[`2026-02-01-D5-2-readme-coverage.md`](./2026-02-01-D5-2-readme-coverage.md)

### 2026-02-03
- **D6 | Foundry Fuzz：D8：ERC721 测试框架（mint / ownerOf / balanceOf）+ fuzz + invariant**  
  - 📄 文档：[`2026-02-03-D6-ERC721-tests.md`](./2026-02-03-D6-ERC721-tests.md)
  - 📄 学习笔记：[`erc721-notes.md`](./erc721-notes.md)
  - 📦 代码：`labs/foundry-labs/src/erc721/SimpleERC721.sol`
  - 🧪 测试：`labs/foundry-labs/test/erc721/SimpleERC721.t.sol`  
  - 关键词：fuzz / erc721 / mint / balanceOf / ownerOf / invariant
  - ▶️ 运行：
  ```bash
  cd labs/foundry-labs
  forge test --match-contract SimpleERC721Test -vvv
  ```

---

## 使用建议
- 每天新增一篇文档后，在本 INDEX 里追加一条记录（日期 + D# + 标题 + 关键词）
- 若你按「每月一个文件夹」组织：建议路径 `docs/2026/02/index.md`（或 `INDEX.md`），统一大小写，避免跨平台大小写差异问题
