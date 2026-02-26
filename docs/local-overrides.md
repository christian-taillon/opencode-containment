# Local Overrides

This project keeps committed defaults minimal and provider-agnostic.

Put personal configuration in local-only files that are gitignored by default.

## Files

- `config/opencode-overrides.local.json`: Optional JSON passed to `OPENCODE_CONFIG_CONTENT`.
- `config/opencode-container.local.sh`: Optional shell hook sourced by `bin/opencode-container`.
- `.zsh_opencode_container.local`: Optional shell-local exports loaded by `container-opencode`.

## Create Local Files

```bash
scripts/init-local-overrides.sh
```

Non-interactive:

```bash
scripts/init-local-overrides.sh --yes
```

Overwrite existing local files:

```bash
scripts/init-local-overrides.sh --yes --force
```

## Layering

`bin/opencode-container` uses this precedence for config content:

1. `OPENCODE_CONFIG_CONTENT` environment variable.
2. `OPENCODE_OVERRIDES_FILE` path (defaults to `config/opencode-overrides.local.json`).
3. No extra config content.

## Keep It Clean

- Keep provider-specific policies in local files only.
- Keep credential passthrough in local hooks only.
- Do not commit tokens, secrets, or personal mount paths.
