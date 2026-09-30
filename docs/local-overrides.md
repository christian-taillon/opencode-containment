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

The container and sandbox launchers have first-class support for the trusted
Jev compaction checkout.

By default, when this directory exists:

```text
$HOME/github/opencode-jev-compactor
```

the launcher exposes it read-only at the same absolute path inside the runtime.
That allows a shared OpenCode config entry such as:

```jsonc
"plugin": [
  [
    "file:///home/christian/github/opencode-jev-compactor/dist/index.js",
    { "delivery": "observe" }
  ]
]
```

Override the checkout path:

```bash
export OPENCODE_JEV_PLUGIN_DIR="$HOME/src/opencode-jev-compactor"
```

or disable the automatic mount:

```bash
export OPENCODE_JEV_PLUGIN_DIR=
```

When `TYPESAFE_API_KEY` is set in the launching shell, both backends pass it
to OpenCode. For Docker Sandboxes, `api.typesafe.ai:443` is included in the
project network allowlist.

For other local plugins, the container backend can use an explicit narrow
read-only mount:

```bash
DOCKER_ARGS+=(--volume "$HOME/github/my-plugin:$HOME/github/my-plugin:ro,Z")
```

The destination must exactly match the path in the plugin's `file://` URL.
Mount only plugin code you trust. Plugins execute inside the OpenCode process
with access to the workspace and mirrored provider authentication.

The sandbox backend ignores `DOCKER_ARGS`; only the dedicated Jev checkout
is exposed automatically as an extra read-only workspace. Other local plugin
checkouts require an explicit sandbox integration or a custom template.
