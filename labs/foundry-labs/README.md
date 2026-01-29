## Foundry

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

