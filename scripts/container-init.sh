#!/usr/bin/env bash
# container-init.sh — runs inside the container on each launch
# Ensures tree-sitter parsers are compiled for Alpine/musl
set -euo pipefail

PARSER_DIR="${HOME}/.local/share/nvim/site/parser"
mkdir -p "$PARSER_DIR"

# Essential parsers that plugins like image.nvim depend on
ESSENTIAL_PARSERS=(
    markdown markdown_inline
    vim lua bash python
    json yaml toml
    javascript typescript
    dockerfile
)

missing=()
for parser in "${ESSENTIAL_PARSERS[@]}"; do
    if [[ ! -f "$PARSER_DIR/${parser}.so" ]]; then
        missing+=("$parser")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "🔧 Compiling tree-sitter parsers for Alpine/musl: ${missing[*]}"
    echo "   (first run only — parsers are cached for future sessions)"
    for p in "${missing[@]}"; do
        printf "   Installing %s... " "$p"
        if nvim --headless +"TSInstallSync ${p}" +qa 2>/dev/null; then
            echo "✓"
        else
            echo "✗ (non-fatal)"
        fi
    done
    echo "✅ Tree-sitter setup complete."
fi

# Execute the original command
exec "$@"
