# D57：GitHub Actions 自动化（forge fmt / forge test）

> 目标：在 **GitHub** 上用 **GitHub Actions** 为你的 Foundry 子项目 `labs/foundry-labs/` 配置 CI 门禁：  
> - `forge fmt --check`（格式检查，快速失败）  
> - `forge test -vvv`（单测/回归，最关键）  
> 可选再加 `forge build` / coverage，但本任务做到 fmt + test 就已经很“作品级”。

---

## 1. 你在这个任务里能学到什么

1) **把“本地能跑”升级成“每次提交都能稳定跑”**  
CI 是团队协作的基本门槛：PR/MR 不通过就不能合并。

2) **快慢分层（门禁设计）**  
- `forge fmt --check`：最快，先卡住格式噪音  
- `forge test`：最重要，验证逻辑正确性  
用 `needs` 让 test 依赖 fmt，节省 CI 时间与排查成本。

3) **子目录工程的 CI 写法**  
你的 Foundry 工程不在 repo 根目录，而在 `labs/foundry-labs/`。  
学会用 `working-directory` 让每个 step 自动在子目录执行。

4) **依赖/子模块稳定性（submodules）**  
Foundry 常把 `forge-std`、OZ 之类放在 `lib/`，有的仓库用 submodule。  
CI 里用 `submodules: recursive`，避免 “CI 找不到依赖”。

5) **缓存提速与可复现**  
缓存 `out/`、`cache/`、`lib/` 等目录，命中时能大幅提速；同时通过 lock/toml hash 控制缓存失效，减少“莫名其妙偶发失败”。

---

## 2. 最终落地文件放哪里

GitHub Actions **只识别** 仓库根目录下的：

```
.github/workflows/*.yml
```

因此你需要新增：

```
/.github/workflows/foundry-labs-ci.yml
```

> 你子目录 `labs/foundry-labs/workflows` **不需要删除**，GitHub 不会执行它。  
> 为避免歧义，你也可以重命名为 `ci-templates/` 或 `notes/`（可选）。

---

## 3. 详细步骤（从 0 到跑通）

### Step 1）新增 workflow 文件

在仓库根目录创建：

**`.github/workflows/foundry-labs-ci.yml`**

```yaml
name: Foundry Labs CI

on:
  push:
    branches: ["**"]
  pull_request:

jobs:
  fmt:
    name: forge fmt --check
    runs-on: ubuntu-latest
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

      - name: Format check
        run: forge fmt --check

  test:
    name: forge test
    runs-on: ubuntu-latest
    needs: fmt
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

      - name: Run tests
        run: forge test -vvv
```

### Step 2）本地提交并推送

```bash
git checkout -b ci/d57-github-actions-foundry
mkdir -p .github/workflows
git add .github/workflows/foundry-labs-ci.yml
git commit -m "ci: add GitHub Actions for forge fmt and tests"
git push -u origin ci/d57-github-actions-foundry
```

### Step 3）在 GitHub 上查看运行

- 打开仓库 → **Actions**  
- push / PR 会自动触发  
- fmt 不过会在 fmt job 直接红灯；fmt 过了才跑 test

---

## 4. 可选增强（更“作品级”）

### 4.1 仅在改动 Solidity/Foundry 配置时触发（降噪）
把 `on:` 改成带 `paths`：

```yaml
on:
  push:
    branches: ["**"]
    paths:
      - "labs/foundry-labs/**/*.sol"
      - "labs/foundry-labs/foundry.toml"
      - "labs/foundry-labs/remappings.txt"
      - ".github/workflows/**"
  pull_request:
    paths:
      - "labs/foundry-labs/**/*.sol"
      - "labs/foundry-labs/foundry.toml"
      - "labs/foundry-labs/remappings.txt"
      - ".github/workflows/**"
```

### 4.2 Fork 测试（需要 RPC）怎么接
如果你有 D50/D51 那种 fork 测试：

1) GitHub → Settings → Secrets and variables → Actions  
新增 secret：`ETH_RPC_URL`

2) 给 `forge test` step 增加 env：

```yaml
- name: Run tests
  env:
    ETH_RPC_URL: ${{ secrets.ETH_RPC_URL }}
  run: forge test -vvv
```

---

## 5. 审计/工程视角 Checklist（快速自查）

- [ ] CI 是否对 PR 强制执行（PR 必过才能合并）  
- [ ] 是否先 fmt 再 test（节省 CI 时间）  
- [ ] 是否在正确目录执行（`labs/foundry-labs`）  
- [ ] 是否拉取 submodules（`lib/` 依赖不缺失）  
- [ ] 是否启用缓存且 key 合理（依赖变更会自动失效）  
- [ ] fork 测试是否把 RPC 放在 Secrets（不写死在仓库）

---

## 6. 本任务产出（你今天做完应得到什么）

1) `.github/workflows/foundry-labs-ci.yml` 已加入仓库  
2) 每次 push/PR 自动跑：`forge fmt --check` + `forge test -vvv`  
3) fork 测试可按需接入 Secrets（为后续 D50+ 打基础）
