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

case "${1:-}" in
    --sandbox-alpha)
        shift
        [[ $# == 0 ]] || { echo 'Unknown sandbox installer argument' >&2; exit 1; }
        require_cmd python3
        require_cmd make
        python3 -B "$ROOT_DIR/scripts/sandbox_alpha.py" setup --workspace "$ROOT_DIR" --no-project-config
        make -C "$ROOT_DIR" shell-install-sandbox-alpha
        echo 'Standalone alpha ready: run opencode-sandbox-alpha from a project.'
        exit 0
        ;;
    --help) echo 'Usage: install.sh [--sandbox-alpha]'; exit 0 ;;
esac
[[ $# == 0 ]] || { echo 'Unknown installer argument' >&2; exit 1; }

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
  3) Optional sandbox backend: make run-sandbox
  4) Legacy opencode2-* command names remain compatibility aliases to the same latest OpenCode runtime
  5) Optional Jev compaction plugin: make setup-jev
  6) Optional: copy opencode-local.example.sh to opencode-local.sh and customize
     - proxy / custom CA passthrough
     - local extra Alpine packages for builds
  6) Optional CLI install: make shell-install

EOF
