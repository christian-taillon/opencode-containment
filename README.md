# opencode-containment

A simple, highly configurable, native-feeling containment starter for OpenCode.

## Just want to contain an AI coding agent?

If you want the shortest path for **Claude Code, Codex, OpenCode, or Cursor**, start with the cross-agent cheat sheet:

- [`docs/cli-containment-cheat-sheet.md`](docs/cli-containment-cheat-sheet.md) — simple Docker Sandboxes and Docker guidance
- [`docs/native-isolation.md`](docs/native-isolation.md) — native isolation by harness, then operating system

The simple rule is:

> Share the project, not your machine.

Docker Sandboxes currently provides the cleanest common interface across the four CLIs:

```bash
sbx run claude
sbx run codex
sbx run cursor
sbx run opencode
```

For a Git repository you do not want the agent editing directly on the host, use clone mode:

```bash
sbx run --clone opencode
```

This repository goes further for OpenCode. The launchers below are the more mature, opinionated path when you want persistent OpenCode state, native-feeling terminal workflows, workspace guardrails, explicit host integration, hardened container defaults, or the Docker Sandboxes backend.

## Overview

Run OpenCode from SSH + tmux + neovim with a native workflow, while keeping strong host safety defaults. tmux runs on the host; the container ships neovim but not tmux. This project is intentionally minimal: a small launcher, a single image build, one local override hook, and a few helper targets you can adapt without digging through framework code.

The tone is practical on purpose: field notes, not framework worship. It is a starting guide, not a final platform. Fork it, tune it, and make it your own.

## Scope

- Built for OpenCode today.
- Easy to adapt for other agent CLIs (Claude Code, Codex, Gemini, and similar tools) with small launcher/image changes.
- Keep the core idea: native terminal UX, clear boundaries, and configurable hardening.

## Demo

This repo includes a prompt injection / data exfiltration demo under `demo/`. It builds a fake lab repo with hidden instructions in common files (README HTML comments, code comments, `copilot-instructions.md`, TODO comments) and shows how agents can be tricked into exfiltrating environment data, and how containment blocks host secrets even when the model follows the instructions. See `demo/README.md` for setup and walkthrough.

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

The pinned OpenCode 2.0 preview is available side by side on x86_64 and arm64
Linux hosts:

```bash
opencode2-container       # v2 container backend
opencode2-sandbox         # v2 Docker Sandboxes backend
opencode2-containment     # convenience alias for opencode2-container
```

These commands do not replace the stable `opencode-container` or
`opencode-sandbox` commands. The preview uses separate default state
directories (`opencode2-container` and `opencode2-sandbox`), shares the host
OpenCode config/data sources for auth seeding, and does not support v1
plugins. It is pinned to `@opencode-ai/cli` beta `0.0.0-beta-18743` and is
subject to upstream beta compatibility changes. The image selects
`cli-linux-x64-baseline-musl` on x86_64 and `cli-linux-arm64-musl` on arm64.

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

The v2 preview has a separate web-server namespace and uses `serve` plus the
v2 health endpoint. The project install does not install a host `opencode2`
binary. When the server URL is reachable from a container, use the contained
client:

```bash
opencode2-container --web-server start
opencode2-container --server http://host.containers.internal:4096
```

The contained client cannot normally reach a loopback-only host listener at
`127.0.0.1`; the example requires a server published on a container-reachable
host address (Podman provides `host.containers.internal`; Docker may require
its equivalent host-gateway address). For the default loopback server, install
the separate beta host CLI and run `opencode2 --server http://127.0.0.1:4096`.
Use the username `opencode` and the generated password
in the credentials file when connecting to a v2 server. The v2 client uses
`--server`; do not use the v1 `attach` command. The same loopback default and
explicit `--network-accessible` opt-in apply.

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

The v2 sibling launchers use the same profiles, workspace guardrails, XDG
sync, and containment defaults. The v2 sandbox uses the local containment
image as its default `sbx` template so that `opencode2` is available; set
`OPENCODE2_SANDBOX_TEMPLATE` when using another template that contains the
preview binary.

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
