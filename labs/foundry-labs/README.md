## Foundry

## Foundry 学习日志（2026/01）

- D1: Foundry 环境搭建 + 第一个测试  
  `docs/2026/01/2026-01-29-foundry-setup-first-test.md`

- D2: Foundry 基础学习（Counter / 测试结构）  
  `docs/2026/01/2026-01-30-Foundry-learn.md`

- D3: ERC-20 allowance 全链路（approve / transferFrom）✅  
  Doc: `docs/2026/01/2026-01-31-erc20-allowance.md`  
  Code: `labs/foundry-labs/src/SimpleERC20.sol`  
  Tests: `labs/foundry-labs/test/SimpleERC20allowance.t.sol`

### D3 一键运行（在 Foundry 工程目录执行）
```bash
cd labs/foundry-labs

# 跑 allowance 测试合集
forge test -vvv --match-contract SimpleERC20AllowanceTest

# 只跑某条用例（示例）
forge test -vvv \
  --match-contract SimpleERC20AllowanceTest \
  --match-test test_transferFrom_reverts_whenAllowanceInsufficient


**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

---

## 4）总索引（INDEX.md）
```md
# INDEX

- 2026-01-29 | Foundry 环境安装 + 创建项目 + 跑通首个 forge test + 第 1 个测试（部署 + 基本断言）
  - Doc: docs/2026/01/2026-01-29-foundry-setup-first-test.md
  - Code: labs/foundry/src/Counter.sol
  - Test: labs/foundry/test/Counter.t.sol

# Foundry Labs

这里存放 Foundry 相关的学习代码与测试用例。

## Quick Start
```bash
forge --version
forge test -vvv

