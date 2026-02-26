#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' is required but not installed or not in PATH." >&2
        exit 1
    fi
}

echo "==> Checking prerequisites"
require_cmd docker
require_cmd make
require_cmd bash

echo "==> Building container image"
make -C "$ROOT_DIR" build

echo "==> Running project setup"
make -C "$ROOT_DIR" setup

echo "==> Running environment checks"
make -C "$ROOT_DIR" doctor || true

cat <<'EOF'

Install complete.

Next steps:
  1) Start the container: make run
  2) Optional secure mode: make run-secure
  3) Optional CLI install: make shell-install

EOF
