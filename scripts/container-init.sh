#!/usr/bin/env bash
set -euo pipefail

echo "========================================================="
echo "[LOCKED] ENFORCED CONTAINMENT ACTIVE"
echo "   - Root filesystem is Read-Only to prevent host modifications."
echo "   - Writable access strictly limited to: /workspace (project dir)"
echo "   - Isolated persistent cache: ~/.local, ~/.cache"
echo "   - Ephemeral temporary storage: /tmp"
echo "========================================================="

export OPENCODE_CONTAINMENT_STRICT="true"
export RESTRICTED_WORKSPACE="/workspace"

exec "$@"
