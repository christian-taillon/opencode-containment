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

The sandbox backend honors `XDG_CONFIG_HOME` and `XDG_DATA_HOME` for its
read-only config and auth mirror. It does not share host cache or runtime state.
