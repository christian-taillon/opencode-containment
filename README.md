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
- Two profiles: `secure` (default) and `native`
- Prepared Neovim parser install directory inside the image
- Read-only container root with explicit writable paths only
- Workspace guardrails to block unsafe mounts
- Read-only host config mounts + SSH agent forwarding (no key mounts)
- One local-only override hook for personal config, mounts, and auth sync

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
3. Run the native profile:
   ```bash
   make run
   # or directly: bin/opencode-container --profile native
   ```
4. Optional: verify your environment:
   ```bash
   make doctor
   ```

## Profiles

The environment supports two profiles to balance security and convenience:

| Feature | `secure` Profile (Default) | `native` Profile |
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

## Command Choices

- `make run`: Starts the native profile for daily use (better editor/shell UX)
- `make run-secure`: Starts the secure profile with minimal integration
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

- `OPENCODE_PROFILE`: Set to `native` to use the native profile (default is `secure`).
- `OPENCODE_IMAGE`: Override the default Docker image.
- `OPENCODE_WORKSPACE`: Override the workspace directory to mount.
- `OPENCODE_OVERRIDES_FILE`: Optional JSON file to pass as `OPENCODE_CONFIG_CONTENT`.

For local customization, copy the tracked example file and keep your personal changes in `opencode-local.sh`:

```bash
cp opencode-local.example.sh opencode-local.sh
```

`bin/opencode-container` sources `opencode-local.sh` before `docker run`, so you can set default profiles, pass JSON config, add mounts or env vars, and sync local auth into the persistent container state without committing any of it.

If you want a sanitized zsh setup, generate it locally in your own script and source or mount it from `opencode-local.sh`. The repo no longer manages that workflow for you.

To install the `opencode-container` command globally in your shell, run:
```bash
make shell-install
```

See `docs/local-overrides.md` for local override layering and examples.

## Makefile Targets

- `make build`: Build the Docker image
- `make setup`: Create necessary persistent directories
- `make doctor`: Verify prerequisites and setup
- `make run`: Run the container interactively (native profile)
- `make run-native`: Run the container interactively (native profile)
- `make run-secure`: Run the container with the secure profile
- `make shell-install`: Install `opencode-container` to `~/.local/bin`
- `make clean`: Remove generated files and persistent state

## Customization

To add new packages or tools to the environment, modify the `Dockerfile` and rebuild the image using `make build`. To adjust mounts or security settings, update the `bin/opencode-container` script.

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
