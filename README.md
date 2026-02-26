# opencode-containment

A simple, highly configurable, native-feeling containment starter for OpenCode.

## Overview

Run OpenCode from SSH + tmux + neovim with a native workflow, while keeping strong host safety defaults. This project is intentionally small and easy to adapt.

## Why

- I run agentic work from a NUC over SSH, living in tmux and neovim where fast terminal workflows matter.
- Many agent projects skip practical containment, even as prompt injection and tool-chain poisoning threats keep growing.
- This aims to be an easy on-ramp: native feel first, with clear options to lock down harder.
- It is a starting guide, not a final platform. Fork it, tune it, and make it your own.

## Features

- Native CLI workflow over SSH/tmux/neovim
- Two profiles: `secure` (default) and `native`
- Read-only container root with explicit writable paths only
- Workspace guardrails to block unsafe mounts
- Read-only host config mounts + SSH agent forwarding (no key mounts)
- Persistent isolated state for cache/local tooling
- Simple launcher script with env-based configuration overrides

## Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/christian-taillon/opencode-containment.git
   cd opencode-containment
   ```
2. Run the installer (recommended):
   ```bash
   ./install.sh
   ```
   This builds the image, runs setup, and checks your environment.

3. (Manual path) Build the container image:
   ```bash
   make build
   ```
4. (Manual path) Set up the environment:
   ```bash
   make setup
   ```
5. (Optional) Verify your setup:
   ```bash
   make doctor
   ```
6. Run the container:
   ```bash
     make run
     # or directly: bin/opencode-container --profile native
   ```

## Profiles

The environment supports two profiles to balance security and convenience:

| Feature | `secure` Profile (Default) | `native` Profile |
|---------|----------------------------|------------------|
| Workspace Mount | Read-Write | Read-Write |
| SSH Agent Socket | Forwarded | Forwarded |
| Host Configs | Git, SSH Config (Read-Only) | Read-Only (git, ssh config) |
| Editor Config | None | Read-Only config/plugins + RW state/cache |
| Shell Config | Default | Sanitized Host Config |

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
+-------------------+       +------------------------+       +-------------------------+
|                   |       |                        |       |                         |
|   Host System     | ----> |  opencode-container    | ----> |  Docker Container       |
|   (Workspace,     |       |  (CLI Wrapper)         |       |  (OpenCode + Dev Tools) |
|   SSH Agent)      |       |  - Applies security    |       |  - /workspace Mount     |
|                   |       |  - Sets up mounts      |       |  - Read-Only Configs    |
+-------------------+       +------------------------+       +-------------------------+
```

## Configuration

You can customize the environment using environment variables:
- `OPENCODE_PROFILE`: Set to `native` to use the native profile (default is `secure`).
- `OPENCODE_IMAGE`: Override the default Docker image.
- `OPENCODE_WORKSPACE`: Override the workspace directory to mount.

To install the `opencode` command globally in your shell, run:
```bash
make shell-install
```

Container configuration overrides (like disabling specific agent delegations) are managed in `config/opencode-overrides.json`.

## Makefile Targets

- `make build`: Build the Docker image
- `make setup`: Create necessary persistent directories
- `make doctor`: Verify prerequisites and setup
- `make run`: Run the container interactively (native profile)
- `make run-secure`: Run the container with the secure profile
- `make shell-install`: Install the `opencode` command globally in your shell
- `make clean`: Remove generated files and persistent state

## Customization

To add new packages or tools to the environment, modify the `Dockerfile` and rebuild the image using `make build`. To adjust mounts or security settings, update the `bin/opencode-container` script.

## Prerequisites

- Docker
- bash

## Contributing

Contributions are welcome. Please keep changes simple, configurable, and security-conscious.

Forks are encouraged - this repository is designed as a practical starting point you can tailor to your own workflow.

## Migration and Handoff

For current migration progress, validation checklist, and host-to-host handoff notes, see `docs/migration-status.md`.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
