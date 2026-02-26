#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSUME_YES="false"
FORCE="false"

usage() {
  cat <<EOF
Usage: scripts/init-local-overrides.sh [--yes] [--force]

Creates local-only override files from tracked examples.

Options:
  --yes     Non-interactive mode (create recommended local files)
  --force   Overwrite existing local files
  --help    Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      ASSUME_YES="true"
      shift
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

prompt_yes_no() {
  local prompt="$1"
  local default_answer="$2"
  local response=""

  if [[ "$ASSUME_YES" == "true" ]]; then
    [[ "$default_answer" == "y" ]]
    return
  fi

  if [[ "$default_answer" == "y" ]]; then
    read -r -p "$prompt [Y/n] " response
    response="${response:-Y}"
  else
    read -r -p "$prompt [y/N] " response
    response="${response:-N}"
  fi

  [[ "$response" =~ ^[Yy]$ ]]
}

copy_template() {
  local source_path="$1"
  local target_path="$2"

  if [[ -f "$target_path" && "$FORCE" != "true" ]]; then
    echo "skip: $target_path already exists (use --force to overwrite)"
    return
  fi

  mkdir -p "$(dirname "$target_path")"
  cp "$source_path" "$target_path"
  echo "wrote: $target_path"
}

if prompt_yes_no "Create config/opencode-overrides.local.json?" "y"; then
  copy_template \
    "$ROOT_DIR/config/opencode-overrides.example.json" \
    "$ROOT_DIR/config/opencode-overrides.local.json"
fi

if prompt_yes_no "Create config/opencode-container.local.sh?" "y"; then
  copy_template \
    "$ROOT_DIR/config/opencode-container.local.sh.example" \
    "$ROOT_DIR/config/opencode-container.local.sh"
  chmod +x "$ROOT_DIR/config/opencode-container.local.sh"
fi

if prompt_yes_no "Create .zsh_opencode_container.local?" "y"; then
  copy_template \
    "$ROOT_DIR/.zsh_opencode_container.local.example" \
    "$ROOT_DIR/.zsh_opencode_container.local"
fi

echo "Done. Local override files are gitignored by default."
