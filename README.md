# opencode-containment

A simple, highly configurable, native-feeling containment starter for OpenCode.

## Overview

Run OpenCode from SSH + tmux + neovim with a native workflow, while keeping strong host safety defaults. This project is intentionally minimal: a small launcher, a single image build, one local override hook, and a few helper targets you can adapt without digging through framework code.

## Why

- I run agentic work from a NUC over SSH, living in tmux and neovim where fast terminal workflows matter.
- Many agent projects skip practical containment, even as prompt injection and tool-chain poisoning threats keep growing.
- This aims to be an easy on-ramp: native feel first, with clear options to lock down harder.
- The tone is practical on purpose: field notes, not framework worship.
- It is a starting guide, not a final platform. Fork it, tune it, and make it your own.

## Scope

- Built for OpenCode today.
- Easy to adapt for other agent CLIs (Claude Code, Codex, Gemini, and similar tools) with small launcher/image changes.
- Keep the core idea: native terminal UX, clear boundaries, and configurable hardening.

## Features

- Native CLI workflow over SSH/tmux/neovim
- Two backends: `container` and `sandbox`
- Two profiles: `secure` (default) and `native`
- One main daily workflow: `make run` (native mode)
- Optional lower-integration mode: `make run-secure` (secure mode)
- Prepared Neovim parser install directory inside the image
- Read-only container root with explicit writable paths only
- Workspace guardrails to block unsafe mounts
- Read-only host config mounts + SSH agent forwarding (no key mounts)
- Host `opencode login` state mirrored into containment by default
- One local-only override hook for personal config, mounts, and auth behavior
- Optional proxy and custom CA passthrough for build/run environments
- Local-only extra Alpine packages during builds without adding a new config system
- More portable launcher path handling for macOS hosts

## Editor Workflow

- The workspace is bind-mounted from your host, so container file changes are visible immediately from host editors.
- You can keep using VS Code, neovim, or any local editor without putting that editor inside the container.
- This keeps container complexity low while preserving a native editing loop.

## Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/christian-taillon/opencode-containment.git
   cd opencode-containment
   ```
2. Build the image and create local state directories:
    ```bash
    ./install.sh
    # or manually:
    # make build
    # make setup
    ```
3. Run the native profile:
    ```bash
    make run
    # or directly: bin/opencode-container --profile native
    ```
4. Pass OpenCode subcommands directly through the launcher:
    ```bash
    opencode-container auth ls
    opencode-container models --refresh
    ```
    Use `--` only when you want to run a raw command in the container:
    ```bash
    opencode-container -- bash
    ```
5. Optional: run the `sandbox` backend instead:
   ```bash
   make run-sandbox
   # or directly: bin/opencode-sandbox --profile native
   ```
6. Optional: verify your environment:
   ```bash
   make doctor
   make doctor-sandbox
   ```

Host OpenCode auth from `~/.local/share/opencode` is mirrored into the container's persistent state automatically, so providers you have already logged into on the host should appear inside `make run` without extra setup.

If you are behind a proxy or need an internal CA bundle, set the standard proxy variables in your shell or `opencode-local.sh` before `make build` / `make run`. They are only passed through when explicitly set.

## Runtime Modes

This project is designed around one main path for daily use:

- `make run` / `--profile native`: recommended default workflow
- `make run-secure` / `--profile secure`: optional lower-integration mode

Both modes exist, but the project is intentionally optimized around the native daily workflow so developers will actually use it.

| Feature | `secure` Mode | `native` Mode |
|---------|----------------------------|------------------|
| Workspace Mount | Read-Write | Read-Write |
| SSH Agent Socket | Forwarded | Forwarded |
| Host Configs | Git, SSH Config (Read-Only) | Read-Only (git, ssh config) |
| Editor Config | None | Read-Only config/plugins + RW state/cache |
| Shell Config | Default | Container Default |

## Backends

- `container` backend: `bin/opencode-container` runs against the local Docker image and exposes the most host integration.
- `sandbox` backend: `bin/opencode-sandbox` runs OpenCode inside Docker Sandboxes and gives `sbx` control over runtime isolation.

| Backend | Launcher | Best for | Tradeoff |
|---------|----------|----------|----------|
| `container` | `bin/opencode-container` | daily local workflow, richer host integration | weaker isolation than a microVM sandbox |
| `sandbox` | `bin/opencode-sandbox` | stronger isolation, cleaner runtime boundary | fewer host-level customization knobs |

## Security Model

Both backends are designed with security as a primary concern:

- **Mounts**: The current workspace is mounted read-write to allow code modifications. Host configuration files (like `.gitconfig`, `.ssh/config`) are mounted read-only to prevent tampering.
- **Excluded Mounts**: Private SSH keys and sensitive environment files are intentionally NOT mounted.
- **SSH Agent**: Instead of mounting keys, the host's SSH agent socket is forwarded, allowing secure authentication without exposing credentials.
- **Environment Variables**: The launchers keep runtime environment passing narrow and explicit.
- **Hardening**: The `container` backend uses explicit container hardening; the `sandbox` backend delegates isolation to `sbx` and its microVM runtime.
- **Filesystem Containment**: The `container` backend uses a read-only root with explicit writable paths. The `sandbox` backend relies on `sbx` to manage sandbox state and isolation.
- **Workspace Guardrails**: The launcher rejects unsafe workspace mounts (`/`, `$HOME`, or paths outside the starting directory tree).
- **OpenCode Auth**: Host OpenCode login state is copied into the container's isolated persistent state before launch. This preserves provider visibility without mounting the entire host home directory.

## Security Non-Negotiables

- Never mount `/`, `$HOME`, or paths outside the active project tree as the workspace.
- Never mount private SSH keys, `.env`, or Docker sockets into the runtime.
- Keep host config mounts read-only unless you have a specific reason not to.
- Treat `opencode-local.sh` as a trust boundary. It can weaken containment if you add unsafe mounts or privileges.
- Prefer the `sandbox` backend when you want stronger runtime isolation than a local container can provide.

## Command Choices

- `make run`: Starts the native profile for daily use (better editor/shell UX)
- `make run-secure`: Starts the secure profile with minimal integration
- `make run-sandbox`: Starts the `sandbox` backend for stronger isolation
- `make shell-install`: Installs `opencode-container` symlink to `~/.local/bin` for convenience

## Architecture

```text
+---------------------------+       +--------------------------+       +----------------------+
| Host System               | ----> | bin/opencode-container   | ----> | Docker Image         |
| - workspace               |       | - profile selection      |       | - OpenCode + tools   |
| - ssh agent               |       | - mount guardrails       |       | - parser dir ready   |
| - optional local config   |       | - local override hook    |       | - container-init     |
+---------------------------+       +--------------------------+       +----------------------+
             \
              \
               +--------------------------+       +----------------------+
               | bin/opencode-sandbox     | ----> | Docker Sandboxes     |
               | - workspace guardrails   |       | - isolated runtime   |
               | - sbx resource flags     |       | - inner Docker       |
               | - local env overrides    |       | - OpenCode agent     |
               +--------------------------+       +----------------------+
```

## Configuration

You can customize the environment with environment variables or a local override script:

- `OPENCODE_PROFILE`: Override the runtime mode (`secure` or `native`). The recommended daily workflow is `make run`, which uses `native`.
- `OPENCODE_IMAGE`: Override the default Docker image.
- `OPENCODE_WORKSPACE`: Override the workspace directory to mount.
- `OPENCODE_OVERRIDES_FILE`: Optional JSON file to pass as `OPENCODE_CONFIG_CONTENT`.
- Standard proxy env vars (`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY`, lowercase variants) are passed through for both runtime and `make build` when set.
- `NODE_EXTRA_CA_CERTS`: Optional custom CA bundle path passed through for runtime and builds when set.
- `OPENCODE_BUILD_EXTRA_APK_PACKAGES`: Optional local-only extra Alpine packages to install during `make build`.
- `OPENCODE_SBX_BIN`: Override the `sbx` binary path for `bin/opencode-sandbox`.
- `OPENCODE_SANDBOX_NAME`: Reuse or create a named sandbox.
- `OPENCODE_SANDBOX_MEMORY`: Pass a memory limit to `sbx run` (default: `8g`).
- `OPENCODE_SANDBOX_CPUS`: Pass a CPU count to `sbx run` (default: `4`).
- `OPENCODE_SANDBOX_TEMPLATE`: Override the sandbox template image.

For local customization, copy the tracked example file and keep your personal changes in `opencode-local.sh`:

```bash
cp opencode-local.example.sh opencode-local.sh
```

`bin/opencode-container` sources `opencode-local.sh` before `docker run`, so you can set default profiles, pass JSON config, add mounts or env vars, and sync local auth into the persistent container state without committing any of it.

`bin/opencode-sandbox` also sources `opencode-local.sh`, but only environment-style settings apply there. Docker-specific `DOCKER_ARGS` customizations do not carry over because `sbx` owns the sandbox runtime and mount model.

`make build` also sources `opencode-local.sh` for proxy/CA and extra APK package overrides. That keeps one local override flow for both runtime and build behavior.

## Security: Local Overrides

`opencode-local.sh` is intentionally powerful. That keeps the repo small, but it also means you can punch holes in the safety model if you are careless.

Avoid these patterns in local overrides:

- mounting `/var/run/docker.sock`
- mounting `/` or all of `$HOME`
- passing `--privileged`
- adding extra Linux capabilities
- copying secrets into writable runtime state unless you mean to persist them

By default, the launcher mirrors host OpenCode auth from `~/.local/share/opencode`. Set `OPENCODE_SYNC_HOST_AUTH=0` in `opencode-local.sh` if you want the container to keep a separate login identity, or set `OPENCODE_HOST_STATE_DIR` to mirror from a different location.

If you want a sanitized zsh setup, generate it locally in your own script and source or mount it from `opencode-local.sh`. The repo no longer manages that workflow for you.

To install the `opencode-container` command globally in your shell, run:
```bash
make shell-install
```

## Sandbox Backend

Use `bin/opencode-sandbox` when you want the same repo workflow on top of Docker Sandboxes instead of the local Docker image. The `sandbox` backend keeps the same workspace guardrails and profile label, but lets `sbx` manage the sandbox filesystem, Docker daemon, and runtime isolation.

This is not trying to clone someone else's `.claude/` or policy layout. The goal here is the same security posture in a simpler shape: one launcher per backend, explicit runtime boundaries, and enough knobs to fit a real SSH-first workflow.

Default sandbox sizing:

```bash
OPENCODE_SANDBOX_MEMORY=8g
OPENCODE_SANDBOX_CPUS=4
```

Override those per host or per run if needed.

Recommended host PATH on Debian-style systems:

```bash
export PATH="$HOME/.docker/sbx/bin:$HOME/.docker/sbx/libexec:/usr/sbin:/sbin:$PATH"
```

Quick checks:

```bash
make doctor-sandbox
bin/opencode-sandbox -- --continue
```

If `sbx` fails to start, check `sbx daemon status`, confirm `/dev/kvm` access, and verify both `mkfs.ext4` and `mkfs.erofs` resolve in your PATH.

See `docs/local-overrides.md` for local override layering and examples.

## macOS Host Notes

- The launcher no longer requires GNU `realpath`; it falls back to portable shell path resolution that works on current macOS hosts.
- Docker Desktop on macOS still runs containers inside a Linux VM. Bind-mounted workspace writes land on the host as usual, but host network/device visibility differs from native Linux.
- Keep expectations realistic: this repo preserves one main recommended workflow with an optional lower-integration mode, not a perfect host-isolation boundary across every Docker Desktop backend detail.

## Makefile Targets

- `make build`: Build the Docker image
- `make setup`: Create necessary persistent directories
- `make doctor`: Verify prerequisites and setup
- `make doctor-sandbox`: Verify Docker Sandboxes prerequisites and host runtime access
- `make run`: Run the container interactively (native profile)
- `make run-native`: Run the container interactively (native profile)
- `make run-secure`: Run the container with the secure profile
- `make run-sandbox`: Run the `sandbox` backend
- `make clean-sandbox-smoke`: Remove the default named smoke-test sandbox
- `make shell-install`: Install `opencode-container` to `~/.local/bin`
- `make clean`: Remove generated files and persistent state

## Customization

To add personal packages without committing Dockerfile changes, set `OPENCODE_BUILD_EXTRA_APK_PACKAGES` in `opencode-local.sh` and rebuild with `make build`. For shared base-image changes, edit the `Dockerfile`. To adjust mounts or security settings, update `bin/opencode-container`.

## Prerequisites

- Docker
- bash

## Dependencies and Guidance

- Core dependencies: Docker, bash, and `make` (used by setup/build helpers).
- Optional host tools: tmux, neovim, VS Code, or any editor you prefer.
- Start simple: run `make build`, `make setup`, then `make run`.
- Harden further as needed: use `make run-secure`, trim mounts, and keep host configs read-only.
- Prefer fork-level customization over adding heavy framework logic here.

## Contributing

Contributions are welcome. Please keep changes simple, configurable, and security-conscious.

Forks are encouraged - this repository is designed as a practical starting point you can tailor to your own workflow.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
