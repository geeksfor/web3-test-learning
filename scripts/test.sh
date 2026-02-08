#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOUNDRY_DIR="${ROOT_DIR}/labs/foundry-labs"

cd "${FOUNDRY_DIR}"

# 默认 -vvv，也允许你额外透传参数
# 示例：./scripts/test.sh --match-contract SimpleERC20Test
echo "[test] forge test -vvv $*"
forge test -vvv "$@"
