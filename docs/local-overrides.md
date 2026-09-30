# Local Overrides

Copy `opencode-local.example.sh` to the gitignored `opencode-local.sh` and set
environment variables there. Keep Docker mounts read-only unless they are
container-owned persistent paths.

## OpenCode XDG sources

The launchers resolve these host OpenCode directories:

- config: `OPENCODE_CONFIG_DIR` or `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`
- data: `OPENCODE_HOST_STATE_DIR` (legacy name) or `${XDG_DATA_HOME:-$HOME/.local/share}/opencode`
- cache: `OPENCODE_HOST_CACHE_DIR` or `${XDG_CACHE_HOME:-$HOME/.cache}/opencode`
- runtime state: `OPENCODE_HOST_RUNTIME_STATE_DIR` or `${XDG_STATE_HOME:-$HOME/.local/state}/opencode`

The container backend mounts config read-only. Data, cache, and runtime state
are copied into `OPENCODE_CONTAINER_HOME`, never mounted writable from the
host. `auth.json`, `account.json`, and `mcp-auth.json` refresh each normal
launch; the session database seeds only when absent. Cache and selected runtime
state seed on first init or explicit refresh.

```bash
export OPENCODE_CONFIG_DIR="$HOME/custom/opencode-config"
export OPENCODE_HOST_STATE_DIR="$HOME/custom/opencode-data"
export OPENCODE_HOST_CACHE_DIR="$HOME/custom/opencode-cache"
export OPENCODE_HOST_RUNTIME_STATE_DIR="$HOME/custom/opencode-state"
```

Set `OPENCODE_SYNC_HOST_AUTH=0`, `OPENCODE_SYNC_CONFIG_CACHE=0`, or
`OPENCODE_SYNC_CONFIG_STATE=0` to skip the corresponding copies. Run
`make sync-config` or `opencode-container --sync-config` to force-refresh
cache/state only; it never replaces `opencode.db`.

The sandbox backend mounts host config read-only and mirrors host auth into a
sandbox-specific read-only auth directory. It does not share host cache/runtime
state.

## OpenCode runtime

The project does not pin a second OpenCode CLI. The containment image follows:

```text
ghcr.io/anomalyco/opencode:latest
```

Run `make update` to pull the current base image and rebuild containment.

The historical `opencode2-*` commands are compatibility aliases only. They
invoke the same current `opencode` runtime.

## Local plugin checkout mounts

For a local `file://` plugin outside the active workspace, set
`OPENCODE_LOCAL_PLUGIN_DIRS` to one or more trusted checkout directories:

```bash
export OPENCODE_LOCAL_PLUGIN_DIRS="$HOME/github/opencode-jev-compactor"
```

Multiple directories use a colon-separated list:

```bash
export OPENCODE_LOCAL_PLUGIN_DIRS="$HOME/github/plugin-a:$HOME/github/plugin-b"
```

Each checkout is canonicalized and mounted read-only at the same absolute path
inside containment. This lets the same OpenCode config work on the host and in
the contained runtime:

```jsonc
{
  "plugin": [
    [
      "file:///home/christian/github/opencode-jev-compactor",
      { "enabled": true, "delivery": "observe" }
    ]
  ]
}
```

The launcher rejects a plugin directory that resolves to `/` or exactly
`$HOME`. Duplicate paths are mounted once.

Container backend: each checkout becomes a read-only bind mount.

Sandbox backend: each checkout becomes a read-only extra workspace when the
named sandbox is created. If you change `OPENCODE_LOCAL_PLUGIN_DIRS` after a
sandbox already exists, remove/recreate that sandbox so the new mount set is
present.

Only mount plugin code you trust. Plugins execute inside the OpenCode process
and can access the writable workspace and mirrored provider credentials.

## Plugin secrets

Selected plugin secrets are passed only when explicitly present in the
launching environment. TypeSafe Jev uses:

```bash
export TYPESAFE_API_KEY='...'
```

The container and sandbox launchers pass `TYPESAFE_API_KEY` through without
mounting a secret file. Do not commit the key to `opencode-local.sh`, OpenCode
config, or this repository.

## Docker-only local customization

`DOCKER_ARGS` remains available for advanced container-backend overrides such
as resource limits or a private provider config:

```bash
DOCKER_ARGS+=(--memory 4g --cpus 2 --pids-limit 512)
```

Docker-specific `DOCKER_ARGS` are ignored by the sandbox backend because
`sbx` owns its runtime boundary. Prefer `OPENCODE_LOCAL_PLUGIN_DIRS` for
plugins because it works across both backends.
