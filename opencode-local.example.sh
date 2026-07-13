#!/usr/bin/env bash
# Local-only configuration for opencode-containment.
#
# Copy to `opencode-local.sh` and customize.
# This file is gitignored - personal settings stay local.
#
# This script is sourced by bin/opencode-container and bin/opencode-sandbox.
# You can set environment variables, modify DOCKER_ARGS for the container backend,
# or set OPENCODE_CONFIG_CONTENT.
#
# Security warning:
# - never mount /var/run/docker.sock
# - never mount / or all of $HOME
# - never add --privileged
# - never add --cap-add
# - never copy .env or private key material into persistent runtime state

# --- Profile & Image Defaults ---
# export OPENCODE_PROFILE="native"
# export OPENCODE_IMAGE="opencode-containment:latest"

# --- Optional Proxy / CA Passthrough ---
# Runtime and docker builds both pass through standard proxy variables only when set.
# Keep NO_PROXY aligned with localhost/127.0.0.1 for the local OpenCode server when needed.
# export HTTPS_PROXY="http://proxy.example:3128"
# export HTTP_PROXY="$HTTPS_PROXY"
# export ALL_PROXY="$HTTPS_PROXY"
# export NO_PROXY="localhost,127.0.0.1"
# export NODE_EXTRA_CA_CERTS="$HOME/.config/opencode/corp-ca.pem"

# --- Optional Extra Alpine Packages For Local Builds ---
# Add local-only packages during `make build` without committing Dockerfile changes.
# export OPENCODE_BUILD_EXTRA_APK_PACKAGES="htop sqlite"

# --- Optional Build Version Pins ---
# Defaults intentionally follow latest/stable. Set these only when you want a
# reproducible or audited local build.
# export RUST_TOOLCHAIN="1.88.0"
# export UV_VERSION="0.11.25"
# export UV_INSTALLER_SHA256="<installer-sha256>"
# export MARKSMAN_VERSION="2026-02-08"
# export MARKSMAN_SHA256_X86_64="<linux-musl-x64-sha256>"
# export MARKSMAN_SHA256_AARCH64="<linux-musl-arm64-sha256>"

# --- OpenCode Config Override (JSON) ---
# Set this to pass custom config into the container:
# export OPENCODE_CONFIG_CONTENT='{"agent":{}}'
#
# Or point to a JSON file (OPENCODE_CONFIG_CONTENT takes precedence):
# export OPENCODE_OVERRIDES_FILE="$HOME/.config/opencode/overrides.json"

# --- Extra Docker Arguments ---
# Example: mount a personal provider config read-only.
# DOCKER_ARGS+=(--volume "$HOME/.config/gcloud:/home/opencode/.config/gcloud:ro")
#
# Offline / audit mode: block all container outbound traffic.
# DOCKER_ARGS+=(--network none)
#
# Resource limits (container backend only; sandbox uses sbx --memory/--cpus).
# DOCKER_ARGS+=(--memory 4g --cpus 2 --pids-limit 512)

# --- Credential Passthrough ---
# Example: pass through personal credentials only when you choose.
# [[ -n "${EXAMPLE_API_KEY:-}" ]] && DOCKER_ARGS+=(--env "EXAMPLE_API_KEY=$EXAMPLE_API_KEY")
# [[ -n "${EXAMPLE_API_SECRET:-}" ]] && DOCKER_ARGS+=(--env "EXAMPLE_API_SECRET=$EXAMPLE_API_SECRET")

# --- OpenCode XDG Sources and Sync ---
# The container resolves four host OpenCode categories. Config is mounted
# read-only; data/cache/runtime-state are copied into isolated container state.
# Defaults honor XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_CACHE_HOME, and
# XDG_STATE_HOME. OPENCODE_HOST_STATE_DIR is the legacy name for the data dir.
#
# export OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
# export OPENCODE_HOST_STATE_DIR="$HOME/.local/share/opencode"
# export OPENCODE_HOST_CACHE_DIR="$HOME/.cache/opencode"
# export OPENCODE_HOST_RUNTIME_STATE_DIR="$HOME/.local/state/opencode"
#
# Host auth/account/MCP-auth files refresh before normal container launches. The
# database seeds only when the container database is absent, preserving container
# sessions. Cache packages can be large and, like selected runtime-state files,
# seed only on first init or an explicit refresh. The sandbox mirrors auth only;
# it does not share host cache/runtime state or seed opencode.db.
#
# Disable it if you want a clean container identity:
# export OPENCODE_SYNC_HOST_AUTH=0
#
# Skip cache or runtime-state seeding:
# export OPENCODE_SYNC_CONFIG_CACHE=0
# export OPENCODE_SYNC_CONFIG_STATE=0
#
# Refresh cache/runtime-state copies on the next normal launch. This never
# overwrites opencode.db. `make sync-config` forces the same refresh and exits.
# export OPENCODE_SYNC_CONFIG_FORCE=1

# Sandbox-only support files, including the read-only auth mirror:
# export OPENCODE_SANDBOX_STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/opencode-sandbox"
