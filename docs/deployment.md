# Deployment Notes — opencode-web-container

This records the host deployment layout and its required V2 server command.
It is not evidence that a service is currently running: the documented user
unit is not installed/active in the current validation environment. The V2
migration does not install or restart it. Verify the deployed unit and drain
sessions/close clients before an authorized rollout.

For the general systemd pattern and V2 client connection
workflow, see [web-server.md](web-server.md).

## V2 deployment target

| Field | Value |
|-------|-------|
| Service | `opencode-web-container.service` (user systemd unit) |
| Image | `localhost/opencode-containment:latest` (locally built) |
| Port | `0.0.0.0:17096` (LAN-accessible) |
| Entrypoint | `opencode serve --hostname 0.0.0.0 --port 17096` |
| Restart policy | `on-failure` (5s delay) |

```bash
systemctl --user status opencode-web-container
journalctl --user -u opencode-web-container -f
```

## Image

The image is built from `~/github/opencode-containment/Dockerfile` and tagged
as `localhost/opencode-containment:latest`. It is **not** available from any
registry — it must be built locally.

Direct Dockerfile builds default to `ghcr.io/anomalyco/opencode:2.1.1` (Alpine,
OpenCode V2 only). The build helper instead resolves the latest stable V2 by
default, or uses an explicit `OPENCODE_VERSION=2.x.y` pin from the environment
or `opencode-local.sh`.
The Dockerfile layers on:

- Rust toolchain (stable), `uv`, Python 3, Node.js, npm
- neovim (with tree-sitter parser dir), marksman (Markdown LSP)
- Git, GitHub CLI, git-crypt, sops, openssh-client
- Shell tools: bash, zsh, ripgrep, fd, fzf, bat, eza, zoxide, direnv
- Build tools: make, build-base, pkgconf, openssl-dev

### Rebuild

```bash
cd ~/github/opencode-containment
podman build --pull -t localhost/opencode-containment:latest .
# For latest V2 via the Docker-compatible CLI (must use the service's image store):
# make update IMAGE_NAME=localhost/opencode-containment:latest
```

Older installed units that invoke `opencode web` must be changed to
`opencode serve`. Rebuild and verify V2 before restarting them; updating the
checkout alone does not migrate a live service.

The build script (`scripts/build-image.sh`) sources `opencode-local.sh` if it
exists, which can set proxy vars, pin versions, or add extra APK packages.
It requires host `curl` for latest-release lookup. Rebuilding does not restart
the service; finish running tasks and close clients before an authorized restart.

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
| `~/.config/opencode` | `/home/opencode/.config/opencode` | RO, `:Z` | Shared config (opencode.json, agents, skills, commands, plugin declarations) |
| `~/github/opencode-jev-compactor` | same absolute path | RO, `:Z` | Trusted local Jev compaction plugin checkout |
| `~/.local/share/opencode-container/local` | `/home/opencode/.local` | RW, `:Z` | Isolated container state (auth, data, sessions) |
| `~/.local/share/opencode-container/cache` | `/home/opencode/.cache` | RW, `:Z` | Isolated container cache |
| `~/.gitconfig` | `/home/opencode/.gitconfig` | RO, `:Z` | Git config |
| `~/.ssh/config` | `/home/opencode/.ssh/config` | RO, `:Z` | SSH config (no keys) |
| `~/.ssh/known_hosts` | `/home/opencode/.ssh/known_hosts` | RO, `:Z` | SSH known hosts |

All mounts use `:Z` for SELinux relabeling (host is SELinux Enforcing).

**Not mounted**: private SSH keys, arbitrary project `.env` files, Docker socket, `/`, or `$HOME`. The Jev checkout is the one intentional sibling-repository plugin mount and remains read-only.

Foreground launcher invocations may additionally use repeatable
`--with-tool COMMAND_OR_PATH`. Each selected executable is snapshotted into a
private temporary directory and mounted read-only at `/opt/opencode-tools` with
snapshot files set to mode `0555`; the original host executable is not mounted.
The detached web-server deployment does not accept this option. Docker uses
`:ro`; Podman adds its `:Z` SELinux relabel option.

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

The private env file may also contain:

```text
TYPESAFE_API_KEY=<TypeSafe System One key>
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
`opencode-containment` repo to seed new state and refresh selected cache/state
files. V2 credentials are in `opencode.db`, which seeds only when the isolated
database is absent and is never replaced by a refresh. Later host sign-in
changes do not update that database; use
`opencode-container auth login --standalone` to update container credentials.

## Connecting

### Web UI

Browse to `http://<host-lan-ip>:17096` (or `http://localhost:17096`).

HTTP Basic Auth:
- Username: `opencode` (fixed by V2)
- Password: value of `OPENCODE_SERVER_PASSWORD` from the env file

### V2 TUI connection

From the host, use the **host** `opencode` binary (not the launcher):

```bash
OPENCODE_PASSWORD='<server-password>' opencode --server http://<host-lan-ip>:17096 /workspace/<project>
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
