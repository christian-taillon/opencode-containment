# Migration Status and Handoff

This document captures the current migration state of the lean containment setup and what to validate on the next host.

## Objective

Ship a secure, native-feeling OpenCode container workflow with a small, easy-to-audit architecture and clear operational handoff.

## Completed Work

- Lean core architecture centered on `Dockerfile`, `bin/opencode-container`, `Makefile`, and `opencode-local.example.sh`
- Hardened Docker runtime wrapper with profile support (`secure`, `native`)
- Alpine-compatible Docker image with core dev tooling and a prepared Neovim parser directory
- Native Neovim host mount strategy (read-only config/plugins with writable persistent state)
- Simplified entrypoint in `scripts/container-init.sh` (banner + exec)
- Single local override pattern via `opencode-local.sh`
- Compatibility additions for prebuilt binaries on Alpine (`gcompat`, `libc6-compat`)
- Sandbox backend (`bin/opencode-sandbox`) with Docker Sandboxes support
- Demo showing prompt injection attacks and containment benefits
- GitHub Actions CI with shell syntax checks, image build, smoke tests, and Trivy scanning
- XDG state seeding across all four base categories (`config`, `data`, `cache`, `state`)
- Proxy and custom CA passthrough for builds and runtime
- `make update` target for refreshing base image and rebuilding

## Current Layout

- `Dockerfile`: builds the environment and installs tools plus parser artifacts
- `bin/opencode-container`: single launcher entry point with mount policy and profile logic
- `bin/opencode-sandbox`: sandbox backend launcher
- `opencode-local.example.sh`: tracked example for local-only overrides copied to `opencode-local.sh`
- `Makefile`: helper targets for build, setup, run, doctor, shell install, update, sync-config, and sandbox policy
- `scripts/build-image.sh`: build helper with proxy/pin support
- `scripts/setup-sandbox-policy.sh`: sandbox network policy setup
- `config/sbx-network-allow.txt`: sandbox network allowlist
- `demo/`: prompt injection demo
- `.github/workflows/ci.yml`: CI pipeline
- Supporting files: `scripts/nvim-wrapper`, `scripts/container-init.sh`, `.gitignore`, `LICENSE`

## Known Constraints

- Host-specific plugin binary artifacts can still vary across machines (especially prebuilt native plugin components).
- Native profile behavior still depends on what you mount from the host, especially personal Neovim config.
- Clipboard behavior in terminal Neovim depends on terminal capabilities on the target host.

## Migration Steps for New Host

1. Install prerequisites: Docker, bash, zsh.
2. Clone repo and build image:
   - `make build`
3. Initialize local runtime directories:
   - `make setup`
4. Optional: create local overrides:
   - `cp opencode-local.example.sh opencode-local.sh`
5. Optional diagnostics:
   - `make doctor`
6. Run native profile:
   - `make run`
7. Optional: stronger isolation with the sandbox backend:
   - `make run-sandbox`
8. Optional: apply sandbox network policy:
   - `make setup-sandbox-policy`

## Validation Checklist on New Host

- OpenCode launches and can access mounted workspace
- Neovim starts with no blocking startup errors
- Markdown buffer opens and parser-dependent plugins initialize
- Markdown LSP (`marksman`) attaches in markdown files
- Git/SSH agent forwarding works for repo operations
- Sandbox backend starts if `sbx` is available
- CI passes on push/PR

## If Something Fails

- Rebuild image: `make build`
- Re-run setup: `make setup`
- Re-test in native mode: `make run`
- Compare with `bin/opencode-container`, `scripts/container-init.sh`, and `Dockerfile` behavior in this repo
