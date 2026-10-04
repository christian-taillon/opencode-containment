# opencode-containment

A simple, highly configurable, native-feeling containment starter for OpenCode.

## Overview

Run OpenCode from SSH + tmux + neovim with a native workflow, while keeping strong host safety defaults. tmux runs on the host; the container ships neovim but not tmux. This project is intentionally minimal: a small launcher, a single image build, one local override hook, and a few helper targets you can adapt without digging through framework code.

The tone is practical on purpose: field notes, not framework worship. It is a starting guide, not a final platform. Fork it, tune it, and make it your own.

## Scope

- Built for OpenCode today.
- Easy to adapt for other agent CLIs (Claude Code, Codex, Gemini, and similar tools) with small launcher/image changes.
- Keep the core idea: native terminal UX, clear boundaries, and configurable hardening.

## Demo

This repo includes a prompt injection / data exfiltration demo under `demo/`. It builds a fake lab repo with hidden instructions in common files (README HTML comments, code comments, `copilot-instructions.md`, TODO comments) and shows how agents can be tricked into exfiltrating environment data, and how containment blocks host secrets even when the model follows the instructions. See `demo/README.md` for setup and walkthrough.

## Standalone Sandboxes alpha

Week-one testers should use the `sandbox-alpha-week1` branch. This opt-in path
is separate from the existing latest-runtime container/sandbox and Jev workflows;
those launchers, image, and host integrations are unchanged. Only this alpha
uses the pinned V2 artifact below. It does not mount a host Jev checkout or
inherit its configuration/auth automatically.

Public **alpha**, not a production-ready or multi-harness release. Live-tested
on one Fedora x86_64 host; other Linux distributions still need fresh-host
validation. Windows, macOS, and arm64 are outside this rollout.

Prerequisites: **Linux x86_64 with accessible KVM, Git, Python 3.9+, Make,
`sbx` v0.46.0 installed, and `sbx login` completed**. Follow Docker's
[Sandboxes installation guide](https://docs.docker.com/ai/sandboxes/) for your
host; `scripts/install-sbx.sh` is a Fedora/Podman-specific helper, not a general
Linux installer. It requires those host tools and rejects AppArmor hosts.

Use a new checkout so existing work and launcher installations are not replaced:

```bash
git clone --branch sandbox-alpha-week1 --single-branch \
  https://github.com/christian-taillon/opencode-containment.git \
  opencode-containment-alpha
cd opencode-containment-alpha
./install.sh --sandbox-alpha  # no Podman/Docker Engine image build
export PATH="$HOME/.local/bin:$PATH"
cd /path/to/your/project
opencode-sandbox-alpha       # V2 UI inside the workspace microVM
```

Ensure `~/.local/bin` is on PATH and keep this checkout (the installed launcher
is a symlink). Installation adds only `opencode-sandbox-alpha` and refuses to
overwrite an unrelated existing launcher. The launcher discovers `sbx` in PATH or its
known user-install locations, starts its daemon when needed, downloads and
verifies pinned V2.0.22 once, and provisions a workspace-specific sandbox.
Defaults: 2 CPUs, 4 GiB, pinned shell template, shared skills off, no host
config/auth imports, and explicit provider-domain network allowances. The
sandbox stops when the UI exits or the launcher receives SIGINT/SIGTERM;
isolated credentials, sessions, and cache persist. No ports are published.

Docker sign-in is **not model-provider sign-in**. Use OpenCode `/connect` then
`/models`, or configure a local provider. Provider authorization remains inside
the sandbox; additional provider endpoints need an explicit trusted allowance.
For the first week, prefer a provider API key or the documented local Ollama
setup. Subscription/browser OAuth is **not validated**; callback flows may not
work without port publication. Do not publish ports to work around it during
this test. Project `opencode.json(c)` can define models, agents, plugins, MCP, and skills.
Global defaults and project override examples are in
[local overrides](docs/local-overrides.md#standalone-sandboxes-alpha).

**Credential boundary:** `/connect` credentials and OAuth tokens persist in
OpenCode's guest database. Explicit `--env` values persist in a private guest
file and enter the process environment. The guest process can access them;
this is not a host-side proxy that injects credentials into outbound requests.
Stopping the sandbox does not erase secrets. See
[credential storage](docs/local-overrides.md#alpha-credential-storage) and
[recovery](docs/local-overrides.md#lifecycle-and-recovery) before resetting anything.

```bash
opencode-sandbox-alpha config   # effective containment defaults/sources; no runtime
opencode-sandbox-alpha doctor   # diagnose runtime/account/sharing settings
opencode-sandbox-alpha status
opencode-sandbox-alpha stop
opencode-sandbox-alpha -- --continue
```

This is **not native host attach** and does not replace the legacy launchers.
The default Sandboxes OpenCode image ships V1, so this path provisions its own
matching V2. Its microVM has a writable root and guest sudo, not container
hardening parity. Name-based runtime operations cannot prevent external
replacement races; resource UUID checks and a per-workspace lock detect ordinary
collisions/replacement. Fixed SSH-agent forwarding and clipboard sharing are
rejected rather than silently changing global `sbx` settings. Fedora remains
outside Docker's supported distro; see [security limits](SECURITY_REPORT.md).

### Week-one tester checklist

Use a disposable clone of a non-sensitive repository, not production code.
The workspace is writable: edits/deletions are real, and workspace secrets are
visible to the agent. Keep credentials out of the test workspace; use only a
test-scoped provider key. Windows, macOS, and arm64 are outside this rollout.

1. Run `opencode-sandbox-alpha doctor`, then launch from the test project.
2. Connect/select a model; try a small explanation, file edit, and shell command.
3. Quit, relaunch, and check your session history and edited files persist.
4. Try a project/global config override if you normally use one. Package
   registries, Git remotes, and MCP endpoints are not generally allowed by the
   provider-only defaults; request specific endpoints rather than broadening
   policy globally.
5. Check `opencode-sandbox-alpha status` after exit: it should be stopped.
   Use `opencode-sandbox-alpha stop` after a crash; do not delete guest state.

Report setup failures and unexpected behavior in
[GitHub issues](https://github.com/christian-taillon/opencode-containment/issues),
with checkout commit (`git rev-parse HEAD` in this checkout), OS/architecture,
`sbx version`, provider/model, sanitized `doctor` output, and minimal reproduction
steps. Review diagnostics before posting; never include keys, auth files,
prompts, private source, or full daemon bundles. Positive feedback is useful too:
note what worked and where setup or daily use felt awkward.

## Quick Start

1. Clone and enter the repository:
   ```bash
   git clone https://github.com/christian-taillon/opencode-containment.git
   cd opencode-containment
   ```
2. Build the image and create local state directories:
   ```bash
   ./install.sh
   ```
3. Start OpenCode in the contained native workflow:
   ```bash
   make run
   ```

That is the normal path. The workspace is your current project directory, mounted read-write at `/workspace`; host config mounts stay read-only, and OpenCode auth is copied into isolated container state.

OpenCode comes directly from `ghcr.io/anomalyco/opencode:latest`. The image does
not install a second pinned preview CLI (the standalone alpha downloads its
own pinned binary separately, not into this image). The historical `opencode2-*` command
names remain compatibility aliases, but they execute the same latest `opencode`
binary and share the same state/runtime semantics.

Useful follow-ups:

```bash
make doctor      # check Docker/image/OpenCode XDG setup
make update      # pull latest upstream pieces and rebuild
make run-secure  # lower-integration container profile
make run-sandbox # sandbox backend (stronger isolation)
make sync-config # force-refresh isolated OpenCode cache/state
```

You can also pass OpenCode subcommands directly through the launcher:

```bash
opencode-container auth ls
opencode-container models --refresh
```

Start a Docker-only local web server with persistent Basic Auth credentials:

```bash
opencode-container --web-server start
# Bare --web-server remains an alias for start.
opencode-container --web-server
# Optional alternate port:
opencode-container --web-server start --web-port 4097
# Inspect or stop the server for this workspace and port:
opencode-container --web-server status --web-port 4097
opencode-container --web-server stop --web-port 4097
```

The legacy `opencode2-container --web-server` command is only a compatibility
alias to the same latest OpenCode web runtime. It uses the same state, health
endpoint, credentials, and lifecycle behavior as `opencode-container`.

The server is published only on `127.0.0.1`. The launcher requires Docker
Engine 28 or later for web-server starts: Docker releases before 28.0.0 can
expose localhost-published ports to other hosts on the same L2 network. The
launcher waits until an unauthenticated request returns `401` and a request
authenticated with the persisted credential file succeeds before printing its
URL. Credentials are stored per workspace and port at
`$OPENCODE_CONTAINER_HOME/web-server/<container-name>.credentials` with mode
`0600` (the containing directory is mode `0700`). `status` reports only service,
bind, resource, and credential-presence metadata; it does not send a request or
read credentials. `stop` preserves the credentials file while removing verified
owned resources. Use the exact `--workspace` path from the emitted teardown
command for lifecycle operations: it is canonical and works from another
directory, including after the workspace is deleted or renamed.

To publish to the LAN, explicitly opt in for each start:

```bash
opencode-container --web-server start --network-accessible
```

This exposes an HTTP server and its Basic Auth credentials on the LAN. That
server can access the mounted workspace and provider credentials, so do not use
this option on untrusted networks. There is intentionally no environment default
for network access.

Each server uses its own user-defined Docker bridge network rather than the
default bridge, preventing ordinary default-bridge containers from reaching it.
It is not Docker's `--internal` network because OpenCode needs outbound access
to provider APIs; it remains reachable from this host only through the
loopback-published port by default. `--network-accessible` also publishes that
port to the LAN. Containers explicitly attached to that network and Docker
daemon administrators remain trusted.

For this entrypoint-independent launch path, a custom `OPENCODE_IMAGE` must
provide `/bin/sh` and the `opencode` executable. A custom image used with
`opencode2-container` must additionally provide `opencode2`.

For running the web server as a **systemd service** (auto-start, restart,
status) and for **attaching a TUI** to a running web server (including the
`/workspace` path translation the container requires), see
[docs/web-server.md](docs/web-server.md).

Use `--` only when you want to run a raw command in the container:

```bash
opencode-container -- bash
```

Import a small, explicit set of host executables for one container launch:

```bash
opencode-container --with-tool rg --with-tool /usr/local/bin/my-tool -- bash
```

`--with-tool` may be repeated and must appear before `--`. A bare name is
resolved by Bash's external-command-only lookup (`type -P`) using the host
PATH; shell builtins, functions, aliases, and unresolved names are rejected.
An explicit path is canonicalized to a regular executable file (including its
symlink target). Each selected file is copied into a private per-launch
staging directory and mounted read-only at `/opt/opencode-tools` with
the snapshot files set to mode `0555`; the original host file is never mounted,
and edits after the snapshot completes do not change that snapshot. The selected
basenames are prepended to a fixed container PATH, not the host PATH, so a
selected name intentionally takes precedence over an image command with the
same name. Duplicate basenames are
rejected. The staging directory is removed when the launcher exits (an
uncatchable `SIGKILL` can leave an orphan for manual cleanup).
Docker uses a `:ro` bind mount; Podman adds its `:Z` SELinux relabel option.
The source is opened before copying to close replacement races after open; a
host process changing the path during the narrow validation/open window or
writing in place during the copy remains outside this shell-level guarantee.

This option is supported by the stable and `opencode2-container` launchers,
including raw and interactive launches. It is rejected with `--web-server`.
It is intended for WSL2 + Docker on Windows and Bash + Docker on Linux or
macOS; native PowerShell and Git Bash launchers are not supported. Only the
selected executable is imported: a selected symlink is snapshotted from its
resolved target, but additional symlink targets and companion
libraries/support files are not copied. Scripts need an interpreter and
dependencies inside the image, and host glibc/Electron/desktop binaries may
fail in the Alpine image; host IPC is not available.

Force-refresh host OpenCode cache and state into isolated container storage
without launching a container:

```bash
opencode-container --sync-config
# or
make sync-config
```

Host OpenCode data is resolved from `OPENCODE_HOST_STATE_DIR` or `XDG_DATA_HOME` and auth is mirrored into isolated container state automatically, so providers you have already logged into on the host should appear inside `make run` without extra setup. The host database is copied only during first-time container state initialization so container-created sessions remain resumable with `opencode-container -s <session-id>`.

If you are behind a proxy or need an internal CA bundle, set the standard proxy variables in your shell or `opencode-local.sh` before `make build` / `make run`. They are only passed through when explicitly set.

## Backends and Profiles

### Backends

- `container` backend: `bin/opencode-container` runs against the local Docker image and exposes the most host integration.
- `sandbox` backend: `bin/opencode-sandbox` runs OpenCode inside Docker Sandboxes and gives `sbx` control over runtime isolation.

| Backend | Launcher | Best for | Tradeoff |
|---------|----------|----------|----------|
| `container` | `bin/opencode-container` | daily local workflow, richer host integration | weaker isolation than a microVM sandbox |
| `sandbox` | `bin/opencode-sandbox` | stronger isolation, cleaner runtime boundary | fewer host-level customization knobs |

Legacy `opencode2-container` and `opencode2-sandbox` names remain available
for compatibility, but they are aliases to the same latest OpenCode runtime.

Default profiles differ between the two launchers. `bin/opencode-container` defaults to the `secure` profile when run directly. `bin/opencode-sandbox` defaults to the `native` profile when run directly. The Makefile targets (`make run`, `make run-native`, `make run-sandbox`) pass `--profile native` explicitly.

### Profiles

This project is designed around one main path for daily use:

- `make run` / `--profile native`: recommended default workflow
- `make run-secure` / `--profile secure`: optional lower-integration mode

| Feature | `secure` Mode | `native` Mode |
|---------|---------------|---------------|
| Workspace Mount | Read-Write | Read-Write |
| SSH Agent Socket | Forwarded | Forwarded |
| Host Configs | Git, SSH Config (Read-Only) | Read-Only (git, ssh config) |
| Editor Config | None | Read-Only config/plugins + RW state/cache |
| Shell Config | Default | Container Default |

### Sandbox Backend Details

Use `bin/opencode-sandbox` when you want the same repo workflow on top of Docker Sandboxes instead of the local Docker image. The `sandbox` backend keeps the same workspace guardrails and profile label, but lets `sbx` manage the sandbox filesystem, Docker daemon, and runtime isolation.

Default sandbox sizing:

```bash
OPENCODE_SANDBOX_MEMORY=8g
OPENCODE_SANDBOX_CPUS=4
```

Sandbox auto-naming: when `OPENCODE_SANDBOX_NAME` is not set, the launcher names the sandbox `opencode-<sanitized-basename>` where the workspace basename is lowercased and any characters other than alphanumerics, `.`, `+`, and `-` are replaced with `-`.

Host auth mirror: host OpenCode auth is copied into a sandbox-specific read-only auth mirror (`$OPENCODE_SANDBOX_STATE_DIR/auth/auth.json`). On each launch a bootstrap script ensures the sandbox's `~/.local/share/opencode/auth.json` points to that mirror via a symlink. The mirror is refreshed from the host every launch; the symlink only recreates itself when needed.

Default network allowlist: the committed `config/sbx-network-allow.txt` only includes Ollama Cloud domains. If you use another model or provider API, add its domains narrowly (for example `api.example.com:443`) and run `make setup-sandbox-policy` before launching the sandbox.

Recommended host PATH on Debian-style systems:

```bash
export PATH="$HOME/.docker/sbx/bin:$HOME/.docker/sbx/libexec:/usr/sbin:/sbin:$PATH"
```

Quick checks:

```bash
make doctor-sandbox
make setup-sandbox-policy
bin/opencode-sandbox -- --continue
```

`make update` rebuilds only the local Docker image used by the container backend. Docker Sandboxes uses its own agent templates, and existing named sandboxes keep their filesystem layer until you remove or recreate them.

## Security

Both backends are designed with security as a primary concern. See [SECURITY_REPORT.md](SECURITY_REPORT.md) for the full threat model, mitigations, accepted risks, and known gaps.

### Security Model

- **Mounts**: The current workspace is mounted read-write to allow code modifications. Host configuration files (like `.gitconfig`, `.ssh/config`) are mounted read-only to prevent tampering.
- **Excluded Mounts**: Private SSH keys and sensitive environment files are intentionally NOT mounted.
- **SSH Agent**: Instead of mounting keys, the host's SSH agent socket is forwarded, allowing secure authentication without exposing credentials.
- **Environment Variables**: The launchers keep runtime environment passing narrow and explicit.
- **Hardening**: The `container` backend uses explicit container hardening (`--cap-drop=ALL`, `--security-opt no-new-privileges`, `--read-only`, `--tmpfs /tmp`, `--init`); the `sandbox` backend delegates isolation to `sbx` and its microVM runtime.
- **Filesystem Containment**: The `container` backend uses a read-only root with explicit writable paths. The `sandbox` backend relies on `sbx` to manage sandbox state and isolation.
- **Workspace Guardrails**: The launcher rejects unsafe workspace mounts (`/`, `$HOME`, or paths outside the starting directory tree).
- **OpenCode Auth**: Host OpenCode login state is copied into the container's isolated persistent state before launch. This preserves provider visibility without mounting the entire host home directory.
- **OpenCode Plugins**: Plugin declarations are visible via the read-only config mount, but plugin code from arbitrary host paths is not available inside the container unless you add a narrow read-only mount in `opencode-local.sh`. Plugins execute with the workspace and mirrored auth available, so only run plugin sources you trust.

### Security Non-Negotiables

- Never mount `/`, `$HOME`, or paths outside the active project tree as the workspace.
- Never mount private SSH keys, `.env`, or Docker sockets into the runtime.
- Keep host config mounts read-only unless you have a specific reason not to.
- Treat `opencode-local.sh` as a trust boundary. It can weaken containment if you add unsafe mounts or privileges.
- Prefer the `sandbox` backend when you want stronger runtime isolation than a local container can provide.

### Local Overrides

`opencode-local.sh` is intentionally powerful. That keeps the repo small, but it also means you can punch holes in the safety model if you are careless.

Avoid these patterns in local overrides:

- mounting `/var/run/docker.sock`
- mounting `/` or all of `$HOME`
- passing `--privileged`
- adding extra Linux capabilities
- copying secrets into writable runtime state unless you mean to persist them

Neither launcher has a built-in `--no-network` flag. To run in offline or audit mode, append `--network none` to `DOCKER_ARGS` in `opencode-local.sh` (container backend only):

```bash
DOCKER_ARGS+=(--network none)
```

This blocks all container outbound traffic, including provider APIs, package managers, and any exfiltration path. It is useful for demos and audit scenarios, but it will also prevent the agent from doing useful online work.

By default, the launcher mirrors host OpenCode auth from `OPENCODE_HOST_STATE_DIR` or `${XDG_DATA_HOME:-$HOME/.local/share}/opencode`. Set `OPENCODE_SYNC_HOST_AUTH=0` in `opencode-local.sh` if you want the container to keep a separate login identity.

If you want a sanitized zsh setup, generate it locally in your own script and source or mount it from `opencode-local.sh`. The repo no longer manages that workflow for you.

## Configuration

You can customize the environment with environment variables or a local override script:

- `OPENCODE_PROFILE`: Override the runtime mode (`secure` or `native`). The recommended daily workflow is `make run`, which uses `native`.
- `OPENCODE_IMAGE`: Override the default Docker image.
- `OPENCODE_WORKSPACE`: Override the workspace directory to mount.
- `OPENCODE_WEB_PORT`: Port for `opencode-container --web-server` (default: `4096`; overridden by `--web-port`). Starts publish only to `127.0.0.1` unless the explicit `--network-accessible` flag is supplied; credentials are scoped to its workspace-and-port container name under `$OPENCODE_CONTAINER_HOME/web-server/`.
- `OPENCODE_OVERRIDES_FILE`: Optional JSON file to pass as `OPENCODE_CONFIG_CONTENT`.
- `OPENCODE_CONTAINER_HOME`: Host directory for container persistent state (default: `$HOME/.local/share/opencode-container`).
- Standard proxy env vars (`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY`, lowercase variants) are passed through for both runtime and `make build` when set.
- `NODE_EXTRA_CA_CERTS`: Optional custom CA bundle path passed through for runtime and builds when set.
- `GITHUB_TOKEN` / `GH_TOKEN`: Passed through to the container if set in the host environment.
- `TYPESAFE_API_KEY`: Passed through when set so the Jev compaction plugin can call TypeSafe System One.
- `OPENCODE_JEV_PLUGIN_DIR`: Trusted local Jev plugin checkout mounted read-only at the same absolute path. Defaults to `$HOME/github/opencode-jev-compactor` when that directory exists; set it empty to disable.
- `OPENCODE_BUILD_EXTRA_APK_PACKAGES`: Optional local-only extra Alpine packages to install during `make build`.
- `OPENCODE_BUILD_NO_CACHE`: Set to `1` to force `--no-cache` on `docker build`.
- `IMAGE_NAME`: Override the image tag for build/run (default: `opencode-containment:latest`).
- Build pin overrides: `RUST_TOOLCHAIN`, `UV_VERSION`, `UV_INSTALLER_SHA256`, `MARKSMAN_VERSION`, `MARKSMAN_SHA256_X86_64`, and `MARKSMAN_SHA256_AARCH64` can be set in `opencode-local.sh` before `make build`.
- `OPENCODE_SYNC_HOST_AUTH`: Set to `0` to skip data-dir auth/account/database seeding (default: `1`).
- `OPENCODE_SYNC_CONFIG_CACHE`: Set to `0` to skip cache-dir seeding (default: `1`).
- `OPENCODE_SYNC_CONFIG_STATE`: Set to `0` to skip runtime-state seeding (default: `1`).
- `OPENCODE_SYNC_CONFIG_FORCE`: Set to `1` to refresh cache/state copies. It never overwrites `opencode.db`.
- `OPENCODE_CONFIG_DIR`: Host config directory mounted read-only (default: `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`).
- `OPENCODE_HOST_STATE_DIR`: Backward-compatible name for the host **data** directory (default: `${XDG_DATA_HOME:-$HOME/.local/share}/opencode`).
- `OPENCODE_HOST_CACHE_DIR`: Host cache seed source (default: `${XDG_CACHE_HOME:-$HOME/.cache}/opencode`).
- `OPENCODE_HOST_RUNTIME_STATE_DIR`: Host runtime-state seed source (default: `${XDG_STATE_HOME:-$HOME/.local/state}/opencode`).
- `OPENCODE_SANDBOX_STATE_DIR`: Host directory for sandbox support files such as the auth mirror (default: `${XDG_DATA_HOME:-$HOME/.local/share}/opencode-sandbox`).
- `OPENCODE_SBX_BIN`: Override the `sbx` binary path for `bin/opencode-sandbox`.
- `OPENCODE_SANDBOX_NAME`: Reuse or create a named sandbox.
- `OPENCODE_SANDBOX_MEMORY`: Pass a memory limit to `sbx run` (default: `8g`).
- `OPENCODE_SANDBOX_CPUS`: Pass a CPU count to `sbx run` (default: `4`).
- `OPENCODE_SANDBOX_TEMPLATE`: Override the sandbox template image.

### XDG OpenCode State

The container launcher resolves all four XDG base categories. Host OpenCode
cache and state are copied into `OPENCODE_CONTAINER_HOME`; no writable host
OpenCode data, cache, or runtime-state directory is mounted.

- **Config (`XDG_CONFIG_HOME`)**: mounted read-only and shared with the host.
- **Data (`XDG_DATA_HOME`)**: `auth.json`, `account.json`, and `mcp-auth.json` refresh each launch; `opencode.db` and its WAL/SHM seed only when the container database is absent.
- **Cache (`XDG_CACHE_HOME`)**: `packages/`, `models.json`, `opencode-quota/`, and `quota-provider-state/` seed first-init only. `packages/` can be large, so it is copied only on first init or an explicit refresh.
- **State (`XDG_STATE_HOME`)**: `model.json`, `kv.json`, and `plugin-meta.json` seed first-init only. Metadata paths for config, data, cache, and state are rewritten for `/home/opencode`; locks, prompt history, frecency, and TUI state are not copied.

`make sync-config` (or `opencode-container --sync-config`) force-refreshes only
the selected cache/state copies, then exits before workspace and Docker checks.
It never overwrites the isolated `opencode.db`. Set
`OPENCODE_SYNC_CONFIG_CACHE=0` or `OPENCODE_SYNC_CONFIG_STATE=0` to opt out.

For the sandbox backend, config and data defaults honor `XDG_CONFIG_HOME` and
`XDG_DATA_HOME`; host config is mounted read-only and host auth is copied into a
sandbox-specific read-only auth mirror. Host cache and runtime state are not
shared. Sandbox sessions and `opencode.db` remain sandbox-local, so native,
container, and sandbox usage do not overwrite each other's session databases.

### OpenCode Plugins

The host OpenCode config directory is mounted read-only, so plugin declarations
are visible inside containment. Plugin source must also exist at the path the
OpenCode config references.

Published plugins can use the container's own package cache. For trusted local
`file://` plugin development, mount only the required checkout read-only at
the same absolute path used in the plugin URL.

The Jev compaction project has first-class support:

Build/validate the checkout once after pulling updates:

```bash
make setup-jev
```

- `$HOME/github/opencode-jev-compactor` is automatically mounted read-only at
  the same absolute path when it exists.
- Override the path with `OPENCODE_JEV_PLUGIN_DIR`.
- Set `OPENCODE_JEV_PLUGIN_DIR=""` to disable the automatic mount.
- `TYPESAFE_API_KEY` is forwarded when it is set.
- The sandbox backend exposes the same checkout as a read-only extra workspace.
- `api.typesafe.ai:443` is included in the project sandbox allowlist.

Example OpenCode configuration:

```jsonc
{
  "plugin": [
    [
      "file:///home/christian/github/opencode-jev-compactor/dist/index.js",
      {
        "enabled": true,
        "delivery": "observe"
      }
    ]
  ]
}
```

Start with `observe`, then switch to `guided-native` after checking the
plugin's persisted diagnostics.

Other local plugins can still be mounted explicitly in `opencode-local.sh`:

```bash
DOCKER_ARGS+=(--volume "$HOME/github/my-plugin:$HOME/github/my-plugin:ro,Z")
```

Plugins execute inside the OpenCode process with access to the mounted
workspace and mirrored provider auth, so treat plugin code as trusted.

### Local Override Hook### Local Override Hook

For local customization, copy the tracked example file and keep your personal changes in `opencode-local.sh`:

```bash
cp opencode-local.example.sh opencode-local.sh
```

`bin/opencode-container` sources `opencode-local.sh` before `docker run`, so you can set default profiles, pass JSON config, add mounts or env vars, and sync local auth into the persistent container state without committing any of it.

See [docs/local-overrides.md](docs/local-overrides.md) for XDG source and sync overrides.

`bin/opencode-sandbox` also sources `opencode-local.sh`, but only environment-style settings apply there. Docker-specific `DOCKER_ARGS` customizations do not carry over because `sbx` owns the sandbox runtime and mount model. Host OpenCode config is readable inside the sandbox by design; keep secrets out of committed or shared config files.

`make build` also sources `opencode-local.sh` for proxy/CA and extra APK package overrides. That keeps one local override flow for both runtime and build behavior.

Config content is resolved in this order:

1. `OPENCODE_CONFIG_CONTENT` environment variable
2. `OPENCODE_OVERRIDES_FILE` path (if set and file exists)
3. No extra config content

Both launchers accept CLI flags that mirror many of these environment variables. Run the launcher with `--help` for the full list. For example:

- `opencode-container --profile`, `--image`, `--workspace`, `--with-tool`, `--web-server`, `--web-port`, `--network-accessible`, `--sync-config`, `--help`
- `opencode-sandbox --profile`, `--workspace`, `--name`, `--memory`, `--cpus`, `--template`, `--help`

The container options are also available through the legacy
`opencode2-container` compatibility alias. The sandbox launchers do not
support `--with-tool`.

### Build and Version Strategy

The committed defaults favor freshness over bit-for-bit reproducibility:

- OpenCode base image: `ghcr.io/anomalyco/opencode:latest`
- Rust: `stable`
- `uv`: latest installer
- `marksman`: latest GitHub release
- Alpine packages: current packages available from the base image repositories at build time

For most personal use, run `make update` periodically. It pulls the latest base image, rebuilds without cache, refreshes package-manager installs, and preserves existing container state.

For reproducible or audited builds, pin versions locally in `opencode-local.sh` before running `make build`:

```bash
export RUST_TOOLCHAIN="1.88.0"
export UV_VERSION="0.11.25"
export UV_INSTALLER_SHA256="<installer-sha256>"
export MARKSMAN_VERSION="2026-02-08"
export MARKSMAN_SHA256_X86_64="<linux-musl-x64-sha256>"
export MARKSMAN_SHA256_AARCH64="<linux-musl-arm64-sha256>"
```

Leave checksum variables empty only when you intentionally want floating latest downloads.

To add personal packages without committing Dockerfile changes, set `OPENCODE_BUILD_EXTRA_APK_PACKAGES` in `opencode-local.sh` and rebuild with `make build`. For shared base-image changes, edit the `Dockerfile`. To adjust mounts or security settings, update `bin/opencode-container`.

## What's in the Container

The image is built on the OpenCode base image (`ghcr.io/anomalyco/opencode:latest`, Alpine-based) and adds:

- OpenCode CLI, neovim (with a prepared tree-sitter parser directory), marksman (Markdown LSP)
- One OpenCode CLI supplied by `ghcr.io/anomalyco/opencode:latest`
- Rust toolchain (stable), `uv` (Python package manager), Python 3, Node.js, npm
- Git, GitHub CLI, git-crypt, sops, openssh-client
- Shell tools: bash, zsh, ripgrep, fd, fzf, bat, eza, zoxide, direnv
- Build tools: make, build-base, pkgconf, openssl-dev

tmux is not installed in the container. It runs on the host and you attach to the container from inside your tmux session.

## Repository Layout

```
bin/            container/sandbox launchers plus legacy opencode2 compatibility aliases
scripts/        build helper, entrypoint, nvim wrapper, sandbox policy setup
config/         sandbox network allowlist
demo/           prompt injection demo
.github/        CI workflow
Dockerfile      image definition
Makefile        build/run/test helper targets
install.sh      one-shot setup
opencode-local.example.sh  tracked example for gitignored local overrides
SECURITY_REPORT.md         security threat model and mitigations
```

## Makefile Targets

- `make build`: Build the Docker image
- `make update`: Pull the base image and rebuild without Docker cache
- `make setup`: Create necessary persistent directories
- `make setup-jev`: Install dependencies, typecheck, build, and test the trusted local Jev compaction checkout
- `make doctor`: Verify prerequisites and setup
- `make doctor-sandbox`: Verify Docker Sandboxes prerequisites and host runtime access
- `make setup-sandbox-policy`: Apply project Docker Sandboxes network allowlist entries
- `make run`: Run the container interactively (native profile)
- `make run-native`: Run the container interactively (native profile)
- `make run-secure`: Run the container with the secure profile
- `make run-sandbox`: Run the `sandbox` backend
- `make run-opencode2`: Compatibility alias for the latest OpenCode container backend
- `make run-opencode2-sandbox`: Compatibility alias for the latest OpenCode sandbox backend
- `make sync-config`: Force-refresh OpenCode cache/state from host into container persistent state without launching a container
- `make clean-sandbox-smoke`: Remove a sandbox named `opencode-containment-smoke` (a convention used for manual sandbox smoke testing; no Makefile target auto-creates it)
- `make shell-install`: Install primary launchers and legacy compatibility aliases to `~/.local/bin`
- `make clean`: Remove generated files and persistent state

## Prerequisites

- Docker, bash, `make`
- Optional host tools: tmux (host-side, not in the container), neovim, VS Code, or any editor you prefer
- The `sandbox` backend additionally requires `sbx` (Docker Sandboxes), KVM access, and `mkfs.ext4`/`mkfs.erofs` in your PATH

## Troubleshooting

- **Image is stale or tools are outdated**: Run `make update` to pull the latest base image and rebuild without cache.
- **Plugins or model state not showing up**: Run `make sync-config` to force-refresh host OpenCode cache/state into container persistent state.
- **Plugin failed to load / missing module**: Verify the checkout is visible at the exact path used by the `file://` URL. The Jev checkout is mounted automatically when it exists at `$HOME/github/opencode-jev-compactor`; other local plugins need an explicit narrow read-only mount.
- **Plugin loads on the host but not in the container**: Its `node_modules` may contain glibc-linked native modules from the host. Rebuild the plugin's dependencies for Alpine/musl, or install the published npm package instead of a local `file://` path.
- **Docker/image/auth setup issues**: Run `make doctor` to check prerequisites, image, SSH agent, and OpenCode host state.
- **Sandbox won't start**: Run `make doctor-sandbox` to check `sbx`, daemon status, KVM access, and filesystem tools. Confirm `/dev/kvm` is accessible and both `mkfs.ext4` and `mkfs.erofs` resolve in your PATH.
- **Sandbox network blocked**: Add your provider's domain to `config/sbx-network-allow.txt` and run `make setup-sandbox-policy`.
- **Podman rootless mount issues**: The launcher detects Podman and applies `keep-id` and `:Z` relabeling automatically. If mounts still fail, check SELinux labels.

## macOS Host Notes

- The launcher does not require GNU `realpath`; it falls back to portable shell path resolution that works on current macOS hosts.
- Docker Desktop on macOS still runs containers inside a Linux VM. Bind-mounted workspace writes land on the host as usual, but host network/device visibility differs from native Linux.
- Keep expectations realistic: this repo preserves one main recommended workflow with an optional lower-integration mode, not a perfect host-isolation boundary across every Docker Desktop backend detail.

## Continuous Integration

GitHub Actions runs on every push to `main`, on pull requests, and can be triggered manually via `workflow_dispatch`. The workflow checks shell script syntax, builds the image, smoke-tests installed tools (`uv`, `rustc`, `marksman`, `opencode`), and scans the built image with Trivy for CRITICAL and HIGH vulnerabilities. Trivy results are uploaded to GitHub Code Scanning.

## Contributing

This is a public repository. Do not commit secrets, personal paths, or sensitive configuration. `opencode-local.sh` is gitignored specifically so you can keep personal overrides local.

Contributions are welcome. Please keep changes simple, configurable, and security-conscious.

Forks are encouraged - this repository is designed as a practical starting point you can tailor to your own workflow.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
