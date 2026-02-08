#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOUNDRY_DIR="${ROOT_DIR}/labs/foundry-labs"

cd "${FOUNDRY_DIR}"

echo "[coverage] generating lcov..."
forge coverage --report lcov

# 有 genhtml 就生成 HTML；没有就提示如何安装
if command -v genhtml >/dev/null 2>&1; then
  rm -rf coverage
  genhtml lcov.info --output-directory coverage
  echo "[coverage] HTML generated: ${FOUNDRY_DIR}/coverage/index.html"
else
  echo "[coverage] genhtml not found; only lcov generated: ${FOUNDRY_DIR}/lcov.info"
  echo "[coverage] tip: install lcov (includes genhtml)."
  echo "          macOS: brew install lcov"
  echo "          ubuntu: sudo apt-get install -y lcov"
fi
