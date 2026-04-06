# opencode-containment

A simple, highly configurable, native-feeling containment starter for OpenCode.

## Overview

Run OpenCode from SSH + tmux + neovim with a native workflow, while keeping strong host safety defaults. This project is intentionally minimal: a small launcher, a single image build, one local override hook, and a few helper targets you can adapt without digging through framework code.

## Why

- I run agentic work from a NUC over SSH, living in tmux and neovim where fast terminal workflows matter.
- Many agent projects skip practical containment, even as prompt injection and tool-chain poisoning threats keep growing.
- This aims to be an easy on-ramp: native feel first, with clear options to lock down harder.
- It is a starting guide, not a final platform. Fork it, tune it, and make it your own.

## Scope

- Built for OpenCode today.
- Easy to adapt for other agent CLIs (Claude Code, Codex, Gemini, and similar tools) with small launcher/image changes.
- Keep the core idea: native terminal UX, clear boundaries, and configurable hardening.

## Features

- Native CLI workflow over SSH/tmux/neovim
- One main daily workflow: `make run`
- Optional lower-integration mode: `make run-secure`
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
    make build
   make setup
   ```
3. Run the main workflow:
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
5. Optional: verify your environment:
   ```bash
   make doctor
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

## Security Model

The container is designed with security as a primary concern:

- **Mounts**: The current workspace is mounted read-write to allow code modifications. Host configuration files (like `.gitconfig`, `.ssh/config`) are mounted read-only to prevent tampering.
- **Excluded Mounts**: Private SSH keys and sensitive environment files are intentionally NOT mounted.
- **SSH Agent**: Instead of mounting keys, the host's SSH agent socket is forwarded, allowing secure authentication without exposing credentials.
- **Environment Variables**: Only an explicit allowlist of environment variables is passed to the container.
- **Hardening**: The container drops unnecessary capabilities (`cap-drop=ALL`), prevents privilege escalation (`no-new-privileges`), maps the container user to the host user to maintain correct file ownership, and uses an image-level startup entrypoint for consistent policy enforcement.
- **Filesystem Containment**: Container root is read-only (`--read-only`) with explicit writable overlays only for `/workspace`, `/tmp`, and isolated persistent cache/state.
- **Workspace Guardrails**: The launcher rejects unsafe workspace mounts (`/`, `$HOME`, or paths outside the starting directory tree).
- **OpenCode Auth**: Host OpenCode login state is copied into the container's isolated persistent state before launch. This preserves provider visibility without mounting the entire host home directory.

## Command Choices

- `make run`: Starts the recommended daily workflow (`native` mode)
- `make run-secure`: Starts the optional lower-integration mode (`secure`)
- `make shell-install`: Installs `opencode-container` symlink to `~/.local/bin` for convenience

## Architecture

```text
+---------------------------+       +--------------------------+       +----------------------+
| Host System               | ----> | bin/opencode-container   | ----> | Docker Image         |
| - workspace               |       | - profile selection      |       | - OpenCode + tools   |
| - ssh agent               |       | - mount guardrails       |       | - parser dir ready   |
| - optional local config   |       | - local override hook    |       | - container-init     |
+---------------------------+       +--------------------------+       +----------------------+
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

For local customization, copy the tracked example file and keep your personal changes in `opencode-local.sh`:

```bash
cp opencode-local.example.sh opencode-local.sh
```

`bin/opencode-container` sources `opencode-local.sh` before `docker run`, so you can set default profiles, pass JSON config, add mounts or env vars, and sync local auth into the persistent container state without committing any of it.

`make build` now uses `scripts/build-image.sh`, which also sources `opencode-local.sh`. That keeps one local override flow for both runtime and build behavior.

Example local-only build additions:

```bash
export OPENCODE_BUILD_EXTRA_APK_PACKAGES="htop sqlite"
export HTTPS_PROXY="http://proxy.example:3128"
export NO_PROXY="localhost,127.0.0.1"
export NODE_EXTRA_CA_CERTS="$HOME/.config/opencode/corp-ca.pem"
```

If extra packages are requested and `apk add` fails, the build stops with a message that includes the requested package list.

By default, the launcher mirrors host OpenCode auth from `~/.local/share/opencode`. Set `OPENCODE_SYNC_HOST_AUTH=0` in `opencode-local.sh` if you want the container to keep a separate login identity, or set `OPENCODE_HOST_STATE_DIR` to mirror from a different location.

If you want a sanitized zsh setup, generate it locally in your own script and source or mount it from `opencode-local.sh`. The repo no longer manages that workflow for you.

To install the `opencode-container` command globally in your shell, run:
```bash
make shell-install
```

See `docs/local-overrides.md` for local override layering and examples.

## macOS Host Notes

- The launcher no longer requires GNU `realpath`; it falls back to portable shell path resolution that works on current macOS hosts.
- Docker Desktop on macOS still runs containers inside a Linux VM. Bind-mounted workspace writes land on the host as usual, but host network/device visibility differs from native Linux.
- Keep expectations realistic: this repo preserves one main recommended workflow with an optional lower-integration mode, not a perfect host-isolation boundary across every Docker Desktop backend detail.

## Makefile Targets

- `make build`: Build the Docker image
- `make setup`: Create necessary persistent directories
- `make doctor`: Verify prerequisites and setup
- `make run`: Run the container interactively in the recommended daily workflow (`native`)
- `make run-native`: Alias for the native daily workflow
- `make run-secure`: Run the container in the optional lower-integration mode (`secure`)
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
