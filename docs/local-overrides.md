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
- Sync auth files or credentials

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
