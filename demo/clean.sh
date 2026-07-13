#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Resetting demo payloads..."
find "$SCRIPT_DIR/repo" -type f \( -name "*.md" -o -name "*.py" \) -exec \
    sed -i'' -E 's#http://[^/[:space:]]+:[0-9]+/#http://LAB_HOST:18888/#g' {} +
echo "  Reset listener host placeholders in: repo/"
echo "  Preserved fake environment file: repo/.env"

if compgen -G "$SCRIPT_DIR/logs/exfil_*.log" > /dev/null; then
    echo "  Logs preserved in: $SCRIPT_DIR/logs/"
    echo "  To remove logs: rm -f $SCRIPT_DIR/logs/exfil_*.log"
fi

echo "Reset complete."
