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

### Alpha credential storage

The following applies only to the standalone alpha, not the host-auth mirroring
used by the existing launchers:

| Data | Location and access |
|------|---------------------|
| `/connect` API keys and OAuth tokens | OpenCode's SQLite database under private guest XDG data. Tokens/keys are available to the guest OpenCode process; use its account UI or `auth` commands to manage them, not direct database edits. |
| Explicit `--env NAME` / global `environment` values | Guest `/home/agent/.local/share/opencode-containment/alpha/environment.json` (mode `0600`), loaded into OpenCode's environment. Refreshes from effective settings each launch; this is persistent storage, not transient stream injection. |
| Guest sessions, cache and runtime state | Under `/home/agent/.local/share/opencode-containment/alpha/`, persisted by `sbx` in its host-backed VM storage. Not stored in the shared project or ordinary host OpenCode state. |
| Launcher records and verified binary cache | `${XDG_DATA_HOME:-~/.local/share}/opencode-containment/sandbox-alpha`, or explicit `--state-dir`. Records contain ownership/configuration metadata, not imported environment values. They are not a backup of guest credentials or sessions. |

Host users/processes with access to the VM storage remain trusted. Private file
modes are not a secret vault or proof that guest tools/plugins cannot read keys.
This project does **not** implement host-side credential injection into provider
request streams. Workspace secrets are readable too, even if gitignored.

Stopping a VM preserves credentials. Removing an environment setting removes it
from the managed guest file on the next successful provisioning, but cannot
erase earlier logs, process copies, provider accounts or backups. To retire a
credential, remove the account through OpenCode as appropriate and revoke it
with the provider. Backups contain secrets: keep them outside the shared
workspace, private, and out of Git and issue reports.

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

The CLI has name-based mutations, so concurrent external `sbx` replacement is
outside this alpha's guarantee. Do not mix direct `sbx` mutations with launcher
operations. Account/runtime replacement is not supported transparent recovery.

#### After a crash or interrupted launch

From the **original project directory**, reuse any original `--config` and
`--state-dir` flags on each launcher command:

```bash
opencode-sandbox-alpha status
opencode-sandbox-alpha stop
opencode-sandbox-alpha
```

If the daemon is stopped, first start the original runtime with
`sbx daemon start --detach` (no policy reset), then retry `status`/`stop`.
Use the same `sbx` executable selected when creating the sandbox, including its
full path if it is not in PATH. If these commands report an ownership, runtime
binding or incomplete-record error, **do not delete state or edit the UUID to
bypass the check**. Follow the inspection steps below. A stopped VM still holds
your sessions and credentials.

#### Locate and inspect the workspace record

Make sure no launcher for this project is still running. In the original
project directory, the default record can be located without printing secrets:

```bash
WORKSPACE="$(pwd -P)"
ALPHA_STATE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode-containment/sandbox-alpha"
# If you used --state-dir, set ALPHA_STATE to that exact absolute path instead.
WORKSPACE_ID="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:20])' "$WORKSPACE")"
RECORD="$ALPHA_STATE/workspaces/$WORKSPACE_ID/instance.json"
python3 -m json.tool "$RECORD"
sbx ls --json
```

Compare the recorded workspace, runtime executable/socket and (if present) UUID
against the original runtime and listing. Do not select a resource by name
alone. `sbx inspect NAME --json` can help inspect sharing, but may include
sensitive metadata; review it locally, not in a public issue. All manual `sbx`
commands below assume the original runtime and no concurrent external mutations.

**Incomplete creation record, and no matching sandbox exists:** after checking
the original runtime listing and ensuring creation is no longer in progress,
archive just the pending record and retry:

```bash
mv -i -- "$RECORD" "$RECORD.pending-$(date -u +%Y%m%dT%H%M%SZ)"
opencode-sandbox-alpha
```

This is only for a record with **no `id` and no sandbox of its recorded name**.
It preserves the record for diagnosis. Do not use it to bypass a missing or
changed resource for a completed record.

**Incomplete record, but a sandbox exists:** do not adopt it or change the record
by hand. If you can establish it was created by your interrupted invocation
(same original runtime and workspace, no conflicting resource), stop that exact
name using `sbx stop NAME`, preserve both the VM and record, and request recovery
help. The alpha has no automatic adoption or supported record-repair command.
If identity is uncertain, stop here rather than mutating someone else's VM.

#### Preserve guest data before considering recreation

For a **completed, verified-owned** sandbox, obtain its name from `status`, quit
the UI, and stop it. To save the managed guest directory to private host storage:

```bash
umask 077
mkdir -p "$HOME/.local/share/opencode-containment-backups"
BACKUP="$(mktemp -d "$HOME/.local/share/opencode-containment-backups/alpha.XXXXXX")"
NAME='replace-with-the-verified-sandbox-name'
opencode-sandbox-alpha stop
sbx cp "$NAME:/home/agent/.local/share/opencode-containment/alpha" "$BACKUP/guest-alpha"
sbx stop "$NAME"
```

Use an existing trusted, user-owned backup parent outside the project; check the
copy succeeded and contains the expected guest data. Copying may need to start
the VM, hence the final stop. Keep the agent/server closed during the copy. This
backs up the managed OpenCode directory, **not** the whole VM or shared workspace.
Back up project edits separately. The alpha has no validated automated restore
or cross-version migration; a copied directory alone is not proof of recovery.
Do not remove the original VM until a suitable restore has been verified.

#### Resource changes, moved projects and upgrades

- **CPU/memory/template changed:** restore the original effective settings to
  reuse the existing VM. The launcher will not resize or recreate it silently.
  To try new settings without deleting sessions, use a separate disposable
  project clone at a different absolute path; it gets a separate sandbox. Keep
  the old VM and record. Do not merely move its record to another state directory.
- **Project moved or deleted:** workspace paths are part of ownership. Restore
  the original directory/path before launcher cleanup where possible; otherwise
  inspect the original record/runtime and seek help. Automatic session transfer
  to a new workspace is not supported.
- **`sbx` changed:** the executable path, SHA-256 and daemon socket are recorded.
  Keep v0.46.0 for this alpha; stop resources before any planned runtime change.
  If the binding differs, do not rewrite it or downgrade a live daemon blindly.
  Preserve the VM/records and request recovery help.
- **Checkout moved / installed link points elsewhere:** the installed launcher
  is a symlink. Inspect `ls -l "$HOME/.local/bin/opencode-sandbox-alpha"`. Restore
  the checkout location, or move aside only your known old symlink and reinstall
  from the intended checkout. Never overwrite an unrelated executable.
- **Cached V2 integrity error:** stop other alpha launch/setup processes. Archive
  `clients/2.0.22/opencode2` and `opencode2.json` together from `ALPHA_STATE`,
  then run `./install.sh --sandbox-alpha` from the intended checkout with the
  same state selection (for custom state, use launcher `setup --state-dir DIR`).
  Only these are disposable host client-cache files. Do not touch `workspaces`,
  guest databases, VM storage or provider auth.

For help, report the error, checkout commit, OS, `sbx version`, and sanitized
reproduction steps in [issues](https://github.com/christian-taillon/opencode-containment/issues).
Never attach guest backups, databases, environment files or full daemon bundles.
Do not use `podman system reset`, delete VM storage, or run broad cleanup commands
as an alpha recovery shortcut.

`sbx` can forward host SSH agents by default. This launcher strips the client
socket environment and rejects a configured fixed socket; it does not change
global daemon settings. To explicitly turn forwarding off for all sandboxes:

```bash
sbx settings set ssh.agentForwardingEnabled false
sbx daemon restart
```

Do not use an existing sandbox that was manually started with forwarded
credentials as an alpha launcher resource; unrecorded sandboxes are not adopted.
