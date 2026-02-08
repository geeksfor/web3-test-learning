# web3-test-learning — Foundry 测试作品集（ERC20 / ERC721）
这是一个用于系统化练习 **Foundry（forge）** 的学习与作品集仓库：围绕 ERC20 / ERC721 合约实现与测试，沉淀可复用的测试模板、检查清单与学习文档。

## 能力矩阵
- ✅ Foundry 常用作弊码：`vm.prank / vm.startPrank / vm.expectRevert`
- ✅ 事件断言：`expectEmit`（Transfer/Approval 等）
- ✅ Fuzz：约束输入 + 性质验证（例如余额守恒）
- ✅ Invariant：长期性质约束（配合 handler / targetContract）
- ✅ ERC721 receiver 场景：`safeTransferFrom` + `IERC721Receiver`（如已覆盖）

> 代码与测试位于 [`labs/foundry-labs/`](./labs/foundry-labs/)；文档索引位于 [`docs/INDEX.md`](./docs/INDEX.md)。

---

## 一键运行（推荐）
> 所有命令都从仓库根目录执行。

```bash
# 1) 初始化（安装依赖 + build）
./scripts/bootstrap.sh

# 2) 跑全部测试
./scripts/test.sh

# 3) 覆盖率（生成 lcov；若系统有 genhtml 会输出 HTML）
./scripts/coverage.sh

# 跑某个测试文件
./scripts/test.sh --match-path test/SimpleERC20.t.sol

# 跑某个测试合约
./scripts/test.sh --match-contract SimpleERC20Test

# 跑某个测试函数
./scripts/test.sh --match-test test_transferFrom_success

# 只跑 fuzz / 调整 fuzz 次数
./scripts/test.sh --match-test testFuzz_ --fuzz-runs 500