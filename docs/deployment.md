# Deployment Notes — opencode-web-container

This documents the actual running deployment of the containerized OpenCode
web server on this host. For the general systemd pattern and TUI attach
workflow, see [web-server.md](web-server.md).

## What's running

| Field | Value |
|-------|-------|
| Service | `opencode-web-container.service` (user systemd unit) |
| Image | `localhost/opencode-containment:latest` (locally built) |
| Port | `0.0.0.0:17096` (LAN-accessible) |
| Entrypoint | `opencode web --hostname 0.0.0.0 --port 17096` |
| Restart policy | `on-failure` (5s delay) |

```bash
systemctl --user status opencode-web-container
journalctl --user -u opencode-web-container -f
```

## Image

The image is built from `~/github/opencode-containment/Dockerfile` and tagged
as `localhost/opencode-containment:latest`. It is **not** available from any
registry — it must be built locally.

Base: `ghcr.io/anomalyco/opencode:latest` (Alpine). The Dockerfile layers on:

- Rust toolchain (stable), `uv`, Python 3, Node.js, npm
- neovim (with tree-sitter parser dir), marksman (Markdown LSP)
- Git, GitHub CLI, git-crypt, sops, openssh-client
- Shell tools: bash, zsh, ripgrep, fd, fzf, bat, eza, zoxide, direnv
- Build tools: make, build-base, pkgconf, openssl-dev

### Rebuild

```bash
cd ~/github/opencode-containment
podman build --pull -t localhost/opencode-containment:latest .
# or via the build script:
# ./scripts/build-image.sh
```

The build script (`scripts/build-image.sh`) sources `opencode-local.sh` if it
exists, which can set proxy vars, pin versions, or add extra APK packages.

### Recovery after `podman system reset`

If the local image is lost (e.g. after `podman system reset`), it must be
rebuilt from source — it cannot be pulled from a registry:

```bash
cd ~/github/opencode-containment
podman build --pull -t localhost/opencode-containment:latest .
systemctl --user restart opencode-web-container.service
```

## Mounts

| Host path | Container path | Mode | Purpose |
|-----------|---------------|------|---------|
| `~/github` | `/workspace` | RW, `:Z` | Project workspace |
| `~/.config/opencode` | `/home/opencode/.config/opencode` | RO, `:Z` | Shared config (opencode.json, agents, skills, commands) |
| `~/.local/share/opencode-container/local` | `/home/opencode/.local` | RW, `:Z` | Isolated container state (auth, data, sessions) |
| `~/.local/share/opencode-container/cache` | `/home/opencode/.cache` | RW, `:Z` | Isolated container cache |
| `~/.gitconfig` | `/home/opencode/.gitconfig` | RO, `:Z` | Git config |
| `~/.ssh/config` | `/home/opencode/.ssh/config` | RO, `:Z` | SSH config (no keys) |
| `~/.ssh/known_hosts` | `/home/opencode/.ssh/known_hosts` | RO, `:Z` | SSH known hosts |

All mounts use `:Z` for SELinux relabeling (host is SELinux Enforcing).

**Not mounted**: private SSH keys, `.env` files, Docker socket, `/`, `$HOME`.

## Container hardening

The container runs with strong containment defaults:

- `--read-only` root filesystem
- `--cap-drop=ALL` (no Linux capabilities)
- `--security-opt no-new-privileges:true`
- `--init` (PID 1 zombie reaping)
- `--user 1000:1000` (non-root, matches host UID via `--userns keep-id`)
- tmpfs at `/tmp` (256M, exec) and `/home/opencode/.config` (16M, noexec)

The entrypoint (`scripts/container-init.sh`) sets `OPENCODE_CONTAINMENT_STRICT=true`
and prints a containment banner before exec'ing the command.

## Environment

Loaded from `~/.config/opencode/opencode-web-container.env`:

```
OPENCODE_SERVER_PASSWORD=<set in your private env file; do not commit>
OPENCODE_ENABLE_EXA=true
```

Additional env vars set inline in the service file:

- `HOME=/home/opencode`
- `EDITOR=nvim`, `VISUAL=nvim`
- `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`, `XDG_STATE_HOME`
  (all pointed at container-internal paths)

## State isolation

Container OpenCode state is isolated from host OpenCode state:

```
~/.local/share/opencode-container/
├── local/     # -> /home/opencode/.local (auth.json, opencode.db, sessions)
├── cache/      # -> /home/opencode/.cache (packages, models, quota)
└── web-server/ # per-workspace web server credentials (if using launcher)
```

Run `make sync-config` (or `opencode-container --sync-config`) from the
`opencode-containment` repo to seed auth and cache from host OpenCode into
the container state directories. This only needs to be done once before
first start, or when host auth changes.

## Connecting

### Web UI

Browse to `http://<host-lan-ip>:17096` (or `http://localhost:17096`).

HTTP Basic Auth:
- Username: `opencode` (default)
- Password: value of `OPENCODE_SERVER_PASSWORD` from the env file

### TUI attach

From the host, use the **host** `opencode` binary (not the launcher):

```bash
opencode attach http://<host-lan-ip>:17096 --dir /workspace/<project>
```

Use the **container path** (`/workspace/<project>`), not the host path
(`~/github/<project>`). The container only sees `/workspace`.

## Service lifecycle

```bash
# Reload after editing the service file
systemctl --user daemon-reload

# Start / stop / restart
systemctl --user start   opencode-web-container
systemctl --user stop    opencode-web-container
systemctl --user restart opencode-web-container

# Status and logs
systemctl --user status opencode-web-container
journalctl --user -u opencode-web-container -f
```

The service is a **user** unit. To start at boot before login, enable lingering:

```bash
loginctl enable-linger $USER
```

## Service file location

```
~/.config/systemd/user/opencode-web-container.service
```

The full unit is also documented in [docs/web-server.md](web-server.md).