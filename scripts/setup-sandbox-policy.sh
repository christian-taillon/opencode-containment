#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOW_FILE="${1:-$ROOT_DIR/config/sbx-network-allow.txt}"
SBX_BIN="${OPENCODE_SBX_BIN:-sbx}"

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

policy_has_resource() {
    local needle="$1"
    local token

    while read -r -a fields; do
        for token in "${fields[@]}"; do
            if [[ "$token" == "$needle" ]]; then
                return 0
            fi
        done
    done <<<"$existing_policies"

    return 1
}

if ! command -v "$SBX_BIN" >/dev/null 2>&1; then
    echo "Error: sbx is not installed or not in PATH." >&2
    exit 1
fi

if [[ ! -f "$ALLOW_FILE" ]]; then
    echo "Error: allowlist does not exist: $ALLOW_FILE" >&2
    exit 1
fi

existing_policies="$($SBX_BIN policy ls 2>/dev/null || true)"
missing_resources=()

while IFS= read -r line || [[ -n "$line" ]]; do
    resource="$(trim "${line%%#*}")"
    [[ -z "$resource" ]] && continue

    if ! policy_has_resource "$resource"; then
        missing_resources+=("$resource")
    fi
done <"$ALLOW_FILE"

if [[ ${#missing_resources[@]} -eq 0 ]]; then
    echo "Sandbox network policy already includes all project allowlist entries."
    exit 0
fi

joined_resources="$(IFS=,; printf '%s' "${missing_resources[*]}")"
"$SBX_BIN" policy allow network "$joined_resources"
