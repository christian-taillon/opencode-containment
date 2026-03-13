#!/usr/bin/env bash
# Local-only configuration for opencode-containment.
#
# Copy to `opencode-local.sh` and customize.
# This file is gitignored - personal settings stay local.
#
# This script is sourced by bin/opencode-container before docker run.
# You can set environment variables, modify DOCKER_ARGS, or set OPENCODE_CONFIG_CONTENT.

# --- Profile & Image Defaults ---
# export OPENCODE_PROFILE="native"
# export OPENCODE_IMAGE="opencode-containment:latest"

# --- OpenCode Config Override (JSON) ---
# Set this to pass custom config into the container:
# export OPENCODE_CONFIG_CONTENT='{"agent":{}}'
#
# Or point to a JSON file (OPENCODE_CONFIG_CONTENT takes precedence):
# export OPENCODE_OVERRIDES_FILE="$HOME/.config/opencode/overrides.json"

# --- Extra Docker Arguments ---
# Example: mount a personal provider config read-only.
# DOCKER_ARGS+=(--volume "$HOME/.config/gcloud:/home/opencode/.config/gcloud:ro")

# --- Credential Passthrough ---
# Example: pass through personal credentials only when you choose.
# [[ -n "${tc_accessid:-}" ]] && DOCKER_ARGS+=(--env "tc_accessid=$tc_accessid")
# [[ -n "${tc_secretkey:-}" ]] && DOCKER_ARGS+=(--env "tc_secretkey=$tc_secretkey")

# --- Auth Sync ---
# Example: sync host auth into container persistent state.
# if [[ -f "$HOME/.local/share/opencode/auth.json" ]]; then
#   mkdir -p "$OPENCODE_CONTAINER_HOME/local/share/opencode"
#   cp "$HOME/.local/share/opencode/auth.json" "$OPENCODE_CONTAINER_HOME/local/share/opencode/auth.json"
# fi
