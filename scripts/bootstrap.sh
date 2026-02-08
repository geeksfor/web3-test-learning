#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOUNDRY_DIR="${ROOT_DIR}/labs/foundry-labs"

echo "[bootstrap] repo: ${ROOT_DIR}"
echo "[bootstrap] foundry project: ${FOUNDRY_DIR}"

if [[ ! -f "${FOUNDRY_DIR}/foundry.toml" ]]; then
  echo "[bootstrap] ERROR: foundry.toml not found in ${FOUNDRY_DIR}"
  exit 1
fi

cd "${FOUNDRY_DIR}"

# 1) 检查 Foundry 是否安装
if ! command -v forge >/dev/null 2>&1; then
  echo "[bootstrap] ERROR: forge not found. Install Foundry first."
  echo "           https://getfoundry.sh/"
  exit 1
fi

echo "[bootstrap] forge version:"
forge --version

# 2) 安装依赖（非 submodule / 不生成 .gitmodules）
# 你如果已经装过，重复执行也不会坏（最多提示已存在）
echo "[bootstrap] installing deps (no git/submodule)..."
forge install foundry-rs/forge-std --no-git
forge install OpenZeppelin/openzeppelin-contracts --no-git

# 3) 编译
echo "[bootstrap] building..."
forge build

echo "[bootstrap] done."
