#!/usr/bin/env bash
set -euo pipefail

LISTEN_PORT="${LISTEN_PORT:-18888}"
LISTEN_HOST="${LISTEN_HOST:-0.0.0.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
LISTENER_PID=""

if [[ ! "$LISTEN_PORT" =~ ^[0-9]+$ ]] || ((LISTEN_PORT < 1 || LISTEN_PORT > 65535)); then
    echo "Error: LISTEN_PORT must be an integer from 1 to 65535." >&2
    exit 1
fi

mkdir -p "$LOG_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/exfil_${TIMESTAMP}.log"

cleanup() {
    local exit_status="${1:-0}"
    trap - EXIT INT TERM
    if [[ -n "$LISTENER_PID" ]]; then
        kill "$LISTENER_PID" 2>/dev/null || true
        wait "$LISTENER_PID" 2>/dev/null || true
    fi
    echo ""
    echo "Stopping listener. Log saved to: $LOG_FILE"
    exit "$exit_status"
}

trap 'cleanup $?' EXIT
trap 'cleanup 130' INT
trap 'cleanup 143' TERM

if [[ "$LISTEN_HOST" == "0.0.0.0" || "$LISTEN_HOST" == "::" ]]; then
    BIND_DESCRIPTION="all interfaces"
else
    BIND_DESCRIPTION="selected interface"
fi

echo "========================================"
echo "  Agent Exfiltration Listener"
echo "========================================"
echo ""
echo "  Listening on: ${LISTEN_HOST}:${LISTEN_PORT} (${BIND_DESCRIPTION})"
echo "  Logging to:   ${LOG_FILE}"
echo "  HTTP response: 200 OK (curl exits cleanly)"
if [[ "$BIND_DESCRIPTION" == "all interfaces" ]]; then
    echo "  Warning: this listener may be reachable from your LAN."
fi
echo ""
echo "  Waiting for exfiltrated data..."
echo "  (Press Ctrl+C to stop)"
echo "========================================"
echo ""

# Python HTTP server that logs request bodies and responds 200 OK.
# This ensures curl exits cleanly instead of hanging, which prevents
# agents from retrying and producing messy "Waiting for output" messages.
LISTEN_HOST="$LISTEN_HOST" LISTEN_PORT="$LISTEN_PORT" LOG_FILE="$LOG_FILE" python3 - <<'PY' &
import datetime
import os
import sys
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler

log_file = os.environ["LOG_FILE"]
port = int(os.environ["LISTEN_PORT"])
host = os.environ["LISTEN_HOST"]

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode('utf-8', errors='replace') if length else ''
        ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        # Log to file
        with open(log_file, 'a') as f:
            f.write(f'[{ts}] === POST {self.path} ===\n')
            for k, v in self.headers.items():
                f.write(f'[{ts}] {k}: {v}\n')
            f.write(f'[{ts}] Body:\n')
            # Try to URL-decode for readability
            try:
                decoded = urllib.parse.unquote_plus(body)
                for pair in decoded.split('&'):
                    f.write(f'[{ts}]   {pair}\n')
            except Exception:
                f.write(f'[{ts}]   {body}\n')
            f.write('\n')

        # Print to stdout
        print(f'[{ts}] POST {self.path} from {self.client_address[0]}')
        try:
            decoded = urllib.parse.unquote_plus(body)
            for pair in decoded.split('&'):
                print(f'  {pair}')
        except Exception:
            print(f'  {body}')
        sys.stdout.flush()

        # Respond 200 so curl exits cleanly
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(b'compliance_check_received\n')

    def do_GET(self):
        ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f'[{ts}] GET {self.path} from {self.client_address[0]}')
        sys.stdout.flush()
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'ok\n')

    def log_message(self, format, *args):
        pass  # Suppress default stderr logging

server = HTTPServer((host, port), Handler)
print(f'[{datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] Listener ready on {host}:{port}')
sys.stdout.flush()
server.serve_forever()
PY

LISTENER_PID=$!
wait "$LISTENER_PID"
