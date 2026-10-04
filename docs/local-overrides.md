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

## Standalone Sandboxes alpha

This section applies only to the opt-in `opencode-sandbox-alpha` launcher, not
the latest-runtime launchers described above. It does not source
`opencode-local.sh`, mirror host auth, or automatically mount the Jev checkout.

`opencode-sandbox-alpha` does not source shell hooks. Containment precedence:

1. Built-in defaults.
2. `${XDG_CONFIG_HOME:-~/.config}/opencode-containment/config.json`.
3. `.opencode-containment.json` in the selected workspace (no ancestor search).
4. Explicit launcher flags.

Global example (all fields optional):

```json
{
  "sandbox": {
    "cpus": 4,
    "memory": "8g",
    "network_allow": ["host.docker.internal:11434", "localhost:11434"],
    "environment": {}
  }
}
```

The example replaces the default external-provider allowances with only local
Ollama access. Network lists replace rather than merge; `--allow-network HOST:PORT`
adds an exact endpoint for that invocation. Existing broader `sbx` policies and
template rules still apply: these allowances are not a complete egress firewall.
The launcher initializes an unconfigured runtime to `deny-all` only if no
sandboxes exist; it never resets existing policy.

Project example:

```json
{"sandbox":{"cpus":2,"memory":"2g"}}
```

Project containment settings can only lower resources within the trusted global
limits. Increasing them requires global config or CLI approval. A project cannot
select host executables, templates, environment variables, networking, or extra
mounts. Unknown fields fail closed. Use `--no-project-config` to ignore that
containment file; it does **not** disable OpenCode's own project configuration.
`config` prints effective settings/sources and only environment names, not values.
Trusted global settings additionally accept `sbx` and `template` overrides.
`--config FILE` selects a trusted global settings file; `--state-dir DIR`
selects private host support storage.

### OpenCode configuration and extensibility

Containment and OpenCode configuration are separate. Optional sandbox-specific
global OpenCode defaults live alongside the containment config in
`opencode-containment/opencode.json`. They are copied into private guest global
config; ordinary project `opencode.json(c)` / `.opencode/opencode.json(c)` override
them using OpenCode's native discovery. Auto-update is disabled globally to keep
the tested version. Existing guest auth and sessions are not overwritten.
Host `~/.config/opencode`, auth, plugins, skills, SSH keys, and MCP registrations
are not automatically copied. Put sandbox-compatible definitions in your
project or the dedicated global file; host-only paths will not work.

Local Ollama global OpenCode example:

```json
{
  "$schema":"https://opencode.ai/config.json",
  "model":"ollama/qwen3.5:4b",
  "providers":{"ollama":{"settings":{"baseURL":"http://host.docker.internal:11434/v1"}}}
}
```

For a new provider, authorize it with `/connect`, select it with `/models`, and
allow any endpoints not covered by the built-in defaults. Raw host environment
forwarding is off; `--env NAME` or `--env NAME=value` is explicit opt-in.
Global `environment` is a map of literal single-line values, never shell code.
Runtime/XDG/loader/SSH/MCP variables are reserved. Imported values live privately
in guest state: do not commit credentials in project configuration.

### Lifecycle and recovery

The launcher uses a hashed canonical workspace name, private host records, a
per-workspace lock, and checks the recorded UUID/workspace before reuse/stop.
Sandbox sessions persist across launches. Default exit and handled interrupts
stop the sandbox; `--keep-running` retains only successful runs. A subsequent
launch stops it before refreshing provisioning. SIGKILL/host crashes cannot run
cleanup: use `opencode-sandbox-alpha stop` afterward.
`stop`/`status` ignore project containment settings and skip launch-only
diagnostics/sharing checks so those cannot block cleanup. Runtime identity is
still verified; a reachable original daemon is required.

Changing creation settings (CPU/memory/template) does not silently recreate or
discard sessions: restore the settings, or explicitly back up guest state,
remove the old sandbox with `sbx`, and archive its `instance.json` before a new
launch. Ambiguous/partial creation preserves the record for manual inspection.
The CLI has name-based mutations, so concurrent external `sbx` replacement is
outside this alpha's guarantee. Do not mix direct `sbx` mutations with launcher
operations. Account/runtime replacement is not supported transparent recovery.

`sbx` can forward host SSH agents by default. This launcher strips the client
socket environment and rejects a configured fixed socket; it does not change
global daemon settings. To explicitly turn forwarding off for all sandboxes:

```bash
sbx settings set ssh.agentForwardingEnabled false
sbx daemon restart
```

Do not use an existing sandbox that was manually started with forwarded
credentials as an alpha launcher resource; unrecorded sandboxes are not adopted.
