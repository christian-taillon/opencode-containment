# Local Overrides

Copy `opencode-local.example.sh` to the gitignored `opencode-local.sh` and set
environment variables there. Keep Docker mounts read-only unless they are
container-owned persistent paths.

## OpenCode XDG sources

The container launcher resolves these host OpenCode directories:

- config: `OPENCODE_CONFIG_DIR` or `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`
- data: `OPENCODE_HOST_STATE_DIR` (legacy name) or `${XDG_DATA_HOME:-$HOME/.local/share}/opencode`
- cache: `OPENCODE_HOST_CACHE_DIR` or `${XDG_CACHE_HOME:-$HOME/.cache}/opencode`
- runtime state: `OPENCODE_HOST_RUNTIME_STATE_DIR` or `${XDG_STATE_HOME:-$HOME/.local/state}/opencode`

Config mounts read-only. Data, cache, and runtime state are copied into
`OPENCODE_CONTAINER_HOME`, never mounted writable from the host. `auth.json`,
`account.json`, and `mcp-auth.json` refresh each normal launch; the session
database seeds only when absent.
Cache (`packages/` can be large) and selected runtime-state files seed only on
first init or an explicit refresh.

```bash
export OPENCODE_CONFIG_DIR="$HOME/custom/opencode-config"
export OPENCODE_HOST_STATE_DIR="$HOME/custom/opencode-data"
export OPENCODE_HOST_CACHE_DIR="$HOME/custom/opencode-cache"
export OPENCODE_HOST_RUNTIME_STATE_DIR="$HOME/custom/opencode-state"
```

Set `OPENCODE_SYNC_HOST_AUTH=0`, `OPENCODE_SYNC_CONFIG_CACHE=0`, or
`OPENCODE_SYNC_CONFIG_STATE=0` to skip their respective copies. Run
`make sync-config` (or `opencode-container --sync-config`) to force-refresh
cache/state only; it never replaces `opencode.db` and exits before Docker or
workspace checks.

## Local plugin development mounts

Use `OPENCODE_PLUGIN_PATHS` for trusted local `file://` plugin checkouts outside the active workspace:

```bash
export OPENCODE_PLUGIN_PATHS="$HOME/github/opencode-jev-compactor"
```

The value is colon-separated when more than one checkout is needed. Each entry must be an absolute directory. The launchers reject `/` and the entire home directory.

The container backend mounts each checkout read-only at the same absolute path, which keeps host OpenCode configuration such as:

```jsonc
"plugin": [
  "file:///home/christian/github/opencode-jev-compactor"
]
```

valid inside the container.

The sandbox backend exposes the same paths as read-only extra workspaces when the sandbox is created. Existing named sandboxes must be recreated after changing `OPENCODE_PLUGIN_PATHS` because sandbox workspace mounts are established at creation time.

Mount the whole plugin repository so its package files and dependencies resolve. Only expose plugins you trust and review: they execute inside the OpenCode process with access to the mounted workspace and available provider credentials.

For TypeSafe-backed plugins, pass the key explicitly:

```bash
export TYPESAFE_API_KEY="..."
```

The container and sandbox launchers forward `TYPESAFE_API_KEY` only when it is set. Keep secrets in the gitignored `opencode-local.sh`, shell environment, or a private service environment file. Do not commit them.

The sandbox backend honors `XDG_CONFIG_HOME` and `XDG_DATA_HOME` for its read-only config and auth mirror. It does not share host cache or runtime state.
