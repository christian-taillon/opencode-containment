# opencode-containment

A secure, native-feeling containerized development environment for OpenCode.

## Overview

This project provides a secure, containerized environment for running OpenCode (an AI coding assistant) directly in your terminal. It wraps a Docker container with security hardening, ensuring that the AI assistant has access to the tools it needs while protecting your host system from unintended modifications.

## Features

- Extends `ghcr.io/anomalyco/opencode` with essential development tools (git, neovim, python3, uv, rust/cargo, build-essential, ripgrep, fd-find)
- Provides a `bin/opencode-container` CLI wrapper for secure `docker run` execution
- Supports two profiles: `secure` (default) and `native` (adds editor and shell config)
- Enforces read-only container root filesystem with writable mounts only where explicitly needed (`/workspace`, `.local`, `.cache`, `/tmp`)
- Mounts workspace read-write, while keeping most host configs read-only
- Forwards SSH agent socket without mounting private keys
- Maintains persistent cache and state across container sessions
- Generates sanitized zshrc to strip secret-loading lines from host config

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
- **Hardening**: The container drops unnecessary capabilities (`cap-drop=ALL`), prevents privilege escalation (`no-new-privileges`), and maps the container user to the host user to maintain correct file ownership.
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
- `make setup`: Create necessary directories and generate sanitized zshrc
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
- zsh (required for the `native` profile shell config generation)

## Contributing

Contributions are welcome! Please ensure that any changes maintain the security model and do not introduce unnecessary privileges or mounts.

## Migration and Handoff

For current migration progress, validation checklist, and host-to-host handoff notes, see `docs/migration-status.md`.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
