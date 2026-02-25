# D58：加 coverage job，生成覆盖率产物（artifact）

> 接着 D57：你已经在 GitHub Actions 里为 `labs/foundry-labs/` 跑通了 `forge fmt --check` 与 `forge test`。  
> D58 的目标是：在 CI 中新增 **coverage job**，产出 **lcov + HTML 覆盖率报告**，并作为 **Artifacts** 可下载留档。  
> 同时解决一个现实问题：**即使 test 失败，也尽量不要阻塞 coverage 产物生成**（便于在失败时仍能看覆盖率/留证据）。

---

## 1）你在这个任务里能学到什么

1. **从“测试是否通过”升级到“测试覆盖到哪里”**  
   覆盖率能暴露未覆盖的分支：权限拒绝路径、revert 分支、边界值（0/1/最大/舍入边界）等。

2. **CI 产物管理（Artifacts）**  
   把 `lcov.info`（机器可读）和 `coverage-html/`（人可读）上传，方便下载、对比、回归留档。

3. **分层设计：test 与 coverage 解耦**  
   覆盖率往往更慢，并且可能被某些“需要环境/故意失败”的测试拖垮。学会：
   - coverage 独立 job
   - 选择性排除不适合做 coverage 的测试集（fork / vulns / invariant 等）

4. **失败也能产出报告：always + continue**  
   使用 `if: always()` 与 `|| true`，让 CI 在出现失败时仍能上传可用的产物（至少保留日志/部分报告）。

---

## 2）目录与前置条件

- Foundry 工程位于：`labs/foundry-labs/`
- GitHub Actions workflow 位于：`.github/workflows/foundry-labs-ci.yml`
- 覆盖率报告产物：
  - `labs/foundry-labs/lcov.info`
  - `labs/foundry-labs/coverage-html/`

> 说明：`forge coverage` 会执行测试路径；若测试本身失败，coverage 可能无法完整产出，这是正常的。  
> 本文会给两种策略：  
> - **A：即便失败也尽量产物**（适合留证据）  
> - **B：排除不适合 coverage 的测试集**（适合稳定产报告）

---

## 3）推荐实现：coverage job（lcov + HTML + Artifacts）

把下面 job 添加到你的 workflow（放在 `jobs:` 下，与 fmt/test 同级）。

### 3.1 版本 A（推荐）：coverage job 永远执行 + 失败也上传

关键点：
- **不依赖 test 成功**（不要 `needs: test`，或只依赖 fmt）
- **job 级别 `if: always()`**
- `forge coverage ... || true`，避免失败直接终止 job
- `upload-artifact` 也用 `if: always()`

```yaml
  coverage:
    name: forge coverage (html artifact)
    runs-on: ubuntu-latest
    if: ${{ always() }}
    defaults:
      run:
        working-directory: labs/foundry-labs
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1
        with:
          version: nightly

      - name: Cache foundry artifacts
        uses: actions/cache@v4
        with:
          path: |
            labs/foundry-labs/out
            labs/foundry-labs/cache
            labs/foundry-labs/lib
          key: ${{ runner.os }}-foundry-${{ hashFiles('labs/foundry-labs/foundry.lock', 'labs/foundry-labs/foundry.toml', 'labs/foundry-labs/remappings.txt') }}

      - name: Install lcov (genhtml)
        run: |
          sudo apt-get update
          sudo apt-get install -y lcov

      - name: Forge coverage (lcov)
        run: |
          forge coverage --report lcov || true
          ls -la
          # 如果没有生成 lcov.info，也不要失败（后续仍能上传已有产物/日志）
          test -f lcov.info || true

      - name: Generate HTML report
        run: |
          mkdir -p coverage-html
          # 有 lcov.info 才生成 html；否则跳过
          test -f lcov.info && genhtml lcov.info --output-directory coverage-html || true

      - name: Upload coverage artifact
        if: ${{ always() }}
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: |
            labs/foundry-labs/coverage-html
            labs/foundry-labs/lcov.info
          retention-days: 14
```

> 适用场景：  
> - 你的主线 test 目前偶尔失败，但你仍希望 CI “至少能留下覆盖率尝试产物/日志”  
> - 你想快速闭环 D58，而不被一堆未修复用例阻塞

---

### 3.2 版本 B（更实用）：排除 fork/vulns/invariant，让 coverage 稳定产出

你当前失败包含：
- fork 测试缺 `ETH_RPC_URL`（D50/D51）
- vulns 漏洞演示用例（D23）可能预期失败或依赖特定条件
- invariant 测试本身在调试中

这类用例通常不适合作为“覆盖率基线”。建议在 coverage job 中排除：

```yaml
      - name: Forge coverage (lcov, exclude fork/vulns/invariant)
        run: |
          forge coverage --report lcov             --no-match-path "test/fork/*"             --no-match-path "test/vulns/*"             --no-match-path "test/*invariant*"             || true
```

> 适用场景：  
> - 你希望 coverage 报告稳定、可持续用于回归比较  
> - fork/vulns/invariant 会单独开 job 或后续逐个修复

---

## 4）Fork 测试的正确打开方式（避免拖垮主线/coverage）

### 4.1 使用 GitHub Secrets 配置 RPC

在 GitHub 仓库：
- Settings → Secrets and variables → Actions → New repository secret
- 添加：`ETH_RPC_URL`

### 4.2 单独 job 跑 fork（只有配置了 secret 才执行）

```yaml
  fork_tests:
    name: fork tests (requires ETH_RPC_URL)
    runs-on: ubuntu-latest
    if: ${{ secrets.ETH_RPC_URL != '' }}
    defaults:
      run:
        working-directory: labs/foundry-labs
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: foundry-rs/foundry-toolchain@v1
        with:
          version: nightly
      - name: Run fork tests
        env:
          ETH_RPC_URL: ${{ secrets.ETH_RPC_URL }}
        run: forge test --match-path "test/fork/*" -vvv
```

> 好处：  
> - 没配 RPC 的环境不会红灯  
> - fork 测试独立执行，不影响主线与 coverage

---

## 5）审计/测试视角 Checklist（拿覆盖率做什么）

- [ ] 权限路径：onlyOwner / role 的 allow + deny 都覆盖了吗？  
- [ ] revert 分支：deadline/nonce/insufficient balance/invalid address 等覆盖了吗？  
- [ ] 边界值：0/1/最大值/舍入边界/精度换算分支覆盖了吗？  
- [ ] 资金流：deposit/withdraw/mint/burn/transfer/approval 关键路径覆盖了吗？  
- [ ] 事件与状态：event + storage 断言覆盖了吗？  

---

## 6）建议的分支与 commit

- 分支：`ci/d58-coverage-artifacts`
- commit：`ci: add coverage job and upload coverage artifacts`

---

## 7）最小排障提示（当 coverage 仍无法生成）

1) 先让 coverage job 使用版本 B 排除 fork/vulns/invariant  
2) 确认 `lcov` 已安装（`genhtml` 来自 lcov 包）  
3) 如果 `lcov.info` 不生成：说明 coverage 执行过程中被失败用例阻断，继续缩小测试集（`--match-path`/`--no-match-path`）
