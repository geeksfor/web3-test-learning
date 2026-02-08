#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOUNDRY_DIR="${ROOT_DIR}/labs/foundry-labs"

cd "${FOUNDRY_DIR}"

echo "[fmt] forge fmt"
forge fmt

echo "[fmt] forge build"
forge build

echo "[fmt] done."
