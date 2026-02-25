#!/usr/bin/env bash
# container-init.sh — runs inside the container on each launch
# Ensures tree-sitter parsers are compiled for Alpine/musl
set -euo pipefail

# nvim-treesitter installs parsers to its plugin directory
TS_PARSER_DIR="${HOME}/.local/share/nvim/lazy/nvim-treesitter/parser"
SITE_PARSER_DIR="${HOME}/.local/share/nvim/site/parser"
mkdir -p "$TS_PARSER_DIR" "$SITE_PARSER_DIR"

# Essential parsers that plugins like image.nvim, render-markdown.nvim depend on
ESSENTIAL_PARSERS=(
    markdown markdown_inline
    vim lua bash python
    json yaml toml
    javascript typescript
    dockerfile
)

missing=()
for parser in "${ESSENTIAL_PARSERS[@]}"; do
    # Check both possible parser locations
    if [[ ! -f "$TS_PARSER_DIR/${parser}.so" ]] && [[ ! -f "$SITE_PARSER_DIR/${parser}.so" ]]; then
        missing+=("$parser")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Compiling tree-sitter parsers for Alpine/musl: ${missing[*]}"
    echo "   (first run only - parsers are cached for future sessions)"
    for p in "${missing[@]}"; do
        printf "   Installing %s... " "$p"
        if nvim --headless +"TSInstallSync ${p}" +qa 2>/dev/null; then
            echo "done"
        else
            echo "skip (non-fatal)"
        fi
    done
    echo "Tree-sitter setup complete."
fi

# Execute the original command
exec "$@"
