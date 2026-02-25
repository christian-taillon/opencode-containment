#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_zshrc="${1:-$HOME/.zshrc}"
target_zshrc="${2:-$repo_root/.zshrc.local}"
tmp_file="${target_zshrc}.tmp"

if [[ ! -f "$source_zshrc" ]]; then
  echo "Source zshrc not found: $source_zshrc" >&2
  exit 1
fi

mkdir -p "$(dirname "$target_zshrc")"

{
  echo "# Generated for container use."
  echo "# Source: $source_zshrc"
  echo "# Secrets/import lines are sanitized."
  echo
} >"$tmp_file"

awk '
  {
    raw = $0
    trimmed = raw
    sub(/^[[:space:]]+/, "", trimmed)

    if (trimmed ~ /^#/) {
      print raw
      next
    }

    is_source = (trimmed ~ /(^|[;[:space:]])source[[:space:]]+/ || trimmed ~ /(^|[;[:space:]])\.[[:space:]]+/)
    is_sensitive = (trimmed ~ /(^|\/)\.zsh_secrets([[:space:]]|$)/ || trimmed ~ /(^|\/)\.zsh_opencode([[:space:]]|$)/ || trimmed ~ /(^|\/)\.env([[:space:]]|$)/ || trimmed ~ /(^|\/)secrets?([[:space:]]|$)/)

    if (is_source && is_sensitive) {
      print "# [container-sanitized] " raw
      next
    }

    print raw
  }
' "$source_zshrc" >>"$tmp_file"

mv "$tmp_file" "$target_zshrc"
chmod 600 "$target_zshrc"

echo "Wrote sanitized zshrc to: $target_zshrc"
