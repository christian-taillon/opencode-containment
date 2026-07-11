# Local Overrides

This project keeps committed defaults minimal and provider-agnostic.

Put personal configuration in `opencode-local.sh` (gitignored by default).

## Setup

Copy the example file and customize:

```bash
cp opencode-local.example.sh opencode-local.sh
```

## What You Can Configure

`opencode-local.sh` is sourced by `bin/opencode-container` before `docker run`. `bin/opencode-sandbox` also sources it, but Docker-specific `DOCKER_ARGS` customizations do not carry over to the sandbox backend; only environment-style settings apply there. Host OpenCode config is readable inside the sandbox by design; keep secrets out of committed or shared config files.

You can:

- Set `OPENCODE_CONFIG_CONTENT` (JSON string passed to the container)
- Set `OPENCODE_OVERRIDES_FILE` (path to a JSON file)
- Set `OPENCODE_PROFILE` or `OPENCODE_IMAGE` defaults
- Set optional proxy or custom CA environment variables for both runtime and builds
- Set `OPENCODE_BUILD_EXTRA_APK_PACKAGES` for local-only extra Alpine packages during image builds
- Set optional build version pins for Rust, `uv`, and `marksman`
- Append to `DOCKER_ARGS` for extra mounts or env vars (container backend only)
- Append to `DOCKER_BUILD_ARGS` for extra `docker build` flags
- Override or disable host OpenCode auth mirroring

## Optional Proxy Support

The launcher and build helper pass through standard proxy settings only when you set them:

- `HTTP_PROXY` / `http_proxy`
- `HTTPS_PROXY` / `https_proxy`
- `ALL_PROXY` / `all_proxy`
- `NO_PROXY` / `no_proxy`
- `NODE_EXTRA_CA_CERTS`

That keeps the default behavior unchanged for normal local builds and runs. If you proxy OpenCode traffic, keep `NO_PROXY=localhost,127.0.0.1` when you need the local TUI server to stay direct.

## Local Build Extras

Use the existing local hook instead of a committed package config file:

```bash
export OPENCODE_BUILD_EXTRA_APK_PACKAGES="htop sqlite"
```

Then run `make build`. The build helper sources `opencode-local.sh`, forwards that value as a build arg, and the Dockerfile installs the extra packages after the base package set.

If an extra package name is wrong or unavailable, the build fails with a clear message listing the requested extra packages.

## Optional Build Pins

The default build follows latest/stable upstream tools. If you need a repeatable local build, set pins before running `make build`:

```bash
export RUST_TOOLCHAIN="1.88.0"
export UV_VERSION="0.11.25"
export UV_INSTALLER_SHA256="<installer-sha256>"
export MARKSMAN_VERSION="2026-02-08"
export MARKSMAN_SHA256_X86_64="<linux-musl-x64-sha256>"
export MARKSMAN_SHA256_AARCH64="<linux-musl-arm64-sha256>"
```

Checksum variables are optional for floating builds and recommended for pinned builds.

## Host OpenCode Auth

By default, the launcher mirrors key host OpenCode state from `~/.local/share/opencode` into the container's persistent `~/.local/share/opencode` before startup. This keeps `opencode login` state and provider visibility aligned between the host and the containment environment.

`auth.json` is refreshed on each launch. The database files are copied only when the container state does not already have `opencode.db`, which prevents sessions created inside the container from being overwritten before `opencode-container -s <session-id>` can resume them.

Mirrored files:

- `auth.json`
- `opencode.db` during first-time initialization only
- `opencode.db-shm` during first-time initialization only
- `opencode.db-wal` during first-time initialization only

Useful overrides in `opencode-local.sh`:

- `export OPENCODE_SYNC_HOST_AUTH=0` to disable mirroring
- `export OPENCODE_HOST_STATE_DIR=/path/to/opencode-state` to mirror data files from a different host directory
- `export OPENCODE_HOST_CACHE_DIR=/path/to/opencode-cache` to override the host cache directory used as a seed source
- `export OPENCODE_HOST_RUNTIME_STATE_DIR=/path/to/opencode-runtime-state` to override the host state directory used as a seed source
- `export OPENCODE_SANDBOX_STATE_DIR=/path/to/opencode-sandbox` to change the sandbox support files directory
- `export OPENCODE_SYNC_CONFIG_FORCE=1` to force re-seeding cache/state into container state, overwriting existing container copies

See `opencode-local.example.sh` for commented examples.

## Precedence

Config content is resolved in this order:

1. `OPENCODE_CONFIG_CONTENT` environment variable
2. `OPENCODE_OVERRIDES_FILE` path (if set and file exists)
3. No extra config content

## Keep It Clean

- Keep provider-specific policies in your local file only
- Keep credential passthrough in your local file only
- Do not commit tokens, secrets, or personal mount paths
- Mirroring copies local auth state into `~/.local/share/opencode-container`, so protect that directory like other local credentials
