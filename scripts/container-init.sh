#!/usr/bin/env bash
set -euo pipefail

echo "========================================================="
echo "[LOCKED] ENFORCED CONTAINMENT ACTIVE"
echo "   - Root filesystem is read-only."
echo "   - Host write access is limited to: /workspace (mounted project dir)."
echo "   - Container-writable state is limited to: ~/.local, ~/.cache, /tmp."
echo "   - Host config mounts are read-only; SSH access uses forwarded agent only."
echo "========================================================="

export OPENCODE_CONTAINMENT_STRICT="true"
export RESTRICTED_WORKSPACE="/workspace"

exec "$@"
