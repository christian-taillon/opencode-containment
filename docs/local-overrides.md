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
- Append to `DOCKER_ARGS` for extra mounts or env vars
- Override or disable host OpenCode auth mirroring

## Host OpenCode Auth

By default, the launcher mirrors key host OpenCode state from `~/.local/share/opencode` into the container's persistent `~/.local/share/opencode` before startup. This keeps `opencode login` state and provider visibility aligned between the host and the containment environment.

Mirrored files:

- `auth.json`
- `opencode.db`
- `opencode.db-shm`
- `opencode.db-wal`

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
