# Local Overrides

This project keeps committed defaults minimal and provider-agnostic.

Put personal configuration in `opencode-local.sh` (gitignored by default).

## Setup

Copy the example file and customize:

```bash
cp opencode-local.example.sh opencode-local.sh
```

## What You Can Configure

`opencode-local.sh` is sourced by `bin/opencode-container` before `docker run`. You can:

- Set `OPENCODE_CONFIG_CONTENT` (JSON string passed to the container)
- Set `OPENCODE_OVERRIDES_FILE` (path to a JSON file)
- Set `OPENCODE_PROFILE` or `OPENCODE_IMAGE` defaults
- Set optional proxy or custom CA environment variables for both runtime and builds
- Set `OPENCODE_BUILD_EXTRA_APK_PACKAGES` for local-only extra Alpine packages during image builds
- Append to `DOCKER_ARGS` for extra mounts or env vars
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
- `export OPENCODE_HOST_STATE_DIR=/path/to/opencode-state` to mirror from a different host directory

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
