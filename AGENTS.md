# AGENTS.md — Operating Manual for AI Agents

Permanent operating instructions for any agent (OpenCode, Claude Code, or other)
working in opencode-containment. Read this first, every session.

## What this project is

opencode-containment is a secure, native-feeling containerized development
environment for OpenCode. It provides a Docker/Podman image, launchers, and
profiles that run OpenCode with strong host-safety defaults: read-only root,
cap-drop ALL, no-new-privileges, isolated state, read-only config mounts.

## Session startup (mandatory order)

1. Read this file.
2. Read `docs/deployment.md` — this documents the actual running deployment
   (image, port, mounts, env, service lifecycle). Review it before touching
   the service file, image, or mounts.
3. Read `README.md` for the full project overview and configuration reference.
4. Read `SECURITY_REPORT.md` before making any security-relevant change.
5. Run `git status`; record branch + HEAD.

## Repository constraints

- The image is built locally as `localhost/opencode-containment:latest`.
  It is **not** available from any registry. If it is lost (e.g. after
  `podman system reset`), it must be rebuilt from the Dockerfile.
- The running web server is a **user systemd unit**
  (`opencode-web-container.service`), not a foreground launcher process.
- All mounts use `:Z` relabeling because the host is SELinux Enforcing.
- Never mount private SSH keys, `.env` files, the Docker socket, `/`, or
  `$HOME` into the container.
- `opencode-local.sh` is gitignored and is a trust boundary — it can weaken
  containment if used carelessly.

## Rules for changes

- Preserve pre-existing user work. No destructive git commands. Local
  commits only; never push/merge/PR unless asked.
- Do not run `podman system reset` or any destructive container command
  without explicit user approval.
- After changing the Dockerfile, rebuild the image and restart the service:
  ```bash
  cd ~/github/opencode-containment
  podman build --pull -t localhost/opencode-containment:latest .
  systemctl --user daemon-reload
  systemctl --user restart opencode-web-container.service
  ```
- After changing the service file:
  ```bash
  systemctl --user daemon-reload
  systemctl --user restart opencode-web-container.service
  ```
- Review your own `git diff` before finishing.

## File ownership conventions

- `Dockerfile` — image definition
- `scripts/build-image.sh` — build helper (sources `opencode-local.sh`)
- `scripts/container-init.sh` — container entrypoint (containment banner + exec)
- `scripts/web-server-entrypoint.sh` — web server credential validation entrypoint
- `scripts/nvim-wrapper` — neovim runtimepath wrapper
- `bin/opencode-container` — container backend launcher
- `bin/opencode-sandbox` — sandbox backend launcher
- `docs/deployment.md` — running deployment reference
- `docs/web-server.md` — systemd service pattern and TUI attach guide
- `docs/local-overrides.md` — XDG source and sync override reference
- `config/sbx-network-allow.txt` — sandbox network allowlist
- `opencode-local.example.sh` — tracked example for local overrides
- `opencode-local.sh` — gitignored local overrides (trust boundary)