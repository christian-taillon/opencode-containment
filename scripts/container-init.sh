#!/usr/bin/env bash
# container-init.sh — runs inside the container on each launch
# Ensures tree-sitter parsers are compiled for Alpine/musl
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

if [[ "${OPENCODE_PROFILE:-}" == "native" ]]; then
    PARSER_DIR="${HOME}/.local/share/nvim/site/parser"
    if ! mkdir -p "$PARSER_DIR" 2>/dev/null; then
        echo "Warning: parser directory is not writable: $PARSER_DIR" >&2
        echo "Skipping parser bootstrap for this session." >&2
        exec "$@"
    fi

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
        if [[ ! -f "$PARSER_DIR/${parser}.so" ]]; then
            missing+=("$parser")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Compiling tree-sitter parsers for Alpine/musl: ${missing[*]}"
        echo "   (first run only - parsers are cached for future sessions)"
        for p in "${missing[@]}"; do
            printf "   Installing %s... " "$p"
            if nvim --headless \
                -c "lua require('nvim-treesitter.configs').setup({ parser_install_dir = '${PARSER_DIR}' }); vim.opt.runtimepath:prepend('${PARSER_DIR}/..')" \
                +"TSInstallSync ${p}" \
                +qa 2>/dev/null; then
                # Verify the parser was actually created
                if [[ -f "$PARSER_DIR/${p}.so" ]]; then
                    echo "done"
                else
                    echo "skip (install succeeded but parser not found)"
                fi
            else
                echo "skip (non-fatal)"
            fi
        done
        echo "Tree-sitter setup complete."
    fi
fi

# Execute the original command
exec "$@"
