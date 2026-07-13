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

Use `--` only when you want to run a raw command in the container:

```bash
opencode-container -- bash
```

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
- `OPENCODE_OVERRIDES_FILE`: Optional JSON file to pass as `OPENCODE_CONFIG_CONTENT`.
- `OPENCODE_CONTAINER_HOME`: Host directory for container persistent state (default: `$HOME/.local/share/opencode-container`).
- Standard proxy env vars (`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY`, lowercase variants) are passed through for both runtime and `make build` when set.
- `NODE_EXTRA_CA_CERTS`: Optional custom CA bundle path passed through for runtime and builds when set.
- `GITHUB_TOKEN` / `GH_TOKEN`: Passed through to the container if set in the host environment.
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

### Local Override Hook

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

- `opencode-container --profile`, `--image`, `--workspace`, `--sync-config`, `--help`
- `opencode-sandbox --profile`, `--workspace`, `--name`, `--memory`, `--cpus`, `--template`, `--help`

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
- Rust toolchain (stable), `uv` (Python package manager), Python 3, Node.js, npm
- Git, GitHub CLI, git-crypt, sops, openssh-client
- Shell tools: bash, zsh, ripgrep, fd, fzf, bat, eza, zoxide, direnv
- Build tools: make, build-base, pkgconf, openssl-dev

tmux is not installed in the container. It runs on the host and you attach to the container from inside your tmux session.

## Repository Layout

```
bin/            launchers (opencode-container, opencode-sandbox)
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
- `make doctor`: Verify prerequisites and setup
- `make doctor-sandbox`: Verify Docker Sandboxes prerequisites and host runtime access
- `make setup-sandbox-policy`: Apply project Docker Sandboxes network allowlist entries
- `make run`: Run the container interactively (native profile)
- `make run-native`: Run the container interactively (native profile)
- `make run-secure`: Run the container with the secure profile
- `make run-sandbox`: Run the `sandbox` backend
- `make sync-config`: Force-refresh OpenCode cache/state from host into container persistent state without launching a container
- `make clean-sandbox-smoke`: Remove a sandbox named `opencode-containment-smoke` (a convention used for manual sandbox smoke testing; no Makefile target auto-creates it)
- `make shell-install`: Install both `opencode-container` and `opencode-sandbox` launchers to `~/.local/bin`
- `make clean`: Remove generated files and persistent state

## Prerequisites

- Docker, bash, `make`
- Optional host tools: tmux (host-side, not in the container), neovim, VS Code, or any editor you prefer
- The `sandbox` backend additionally requires `sbx` (Docker Sandboxes), KVM access, and `mkfs.ext4`/`mkfs.erofs` in your PATH

## Troubleshooting

- **Image is stale or tools are outdated**: Run `make update` to pull the latest base image and rebuild without cache.
- **Plugins or model state not showing up**: Run `make sync-config` to force-refresh host OpenCode cache/state into container persistent state.
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
