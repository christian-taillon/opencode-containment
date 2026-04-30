#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Cleaning up demo artifacts..."
find "$SCRIPT_DIR/repo" -type f \( -name "*.md" -o -name "*.py" \) -exec \
    sed -i'' -E 's#http://[^/:]+:8888/#http://LAB_HOST:8888/#g' {} + 2>/dev/null || true
echo "  Reset listener host placeholders in: repo/"

if [[ -d "$SCRIPT_DIR/logs" ]] && compgen -G "$SCRIPT_DIR/logs/*" > /dev/null; then
    echo "  Logs preserved in: $SCRIPT_DIR/logs/"
    echo "  To remove logs: rm -rf $SCRIPT_DIR/logs/"
fi

echo "Done."
