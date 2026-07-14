# Web Server and Remote Attach

The launcher's `--web-server` mode runs `opencode web` inside a detached
container with persistent Basic Auth credentials. See the
[README](../README.md#quick-start) for the built-in lifecycle commands
(`start`, `stop`, `status`, `--web-port`, `--network-accessible`).

This doc covers two related patterns the launcher does not manage for you:

1. Running the web server as a **systemd service** (auto-start, restart,
   status) using a custom container image and port.
2. **Attaching a TUI** to a running web server, including the path
   translation you need when the server runs inside a container.

## systemd service

The launcher's `--web-server` is a foreground command that blocks until you
stop it. If you want the containerized web server to start at boot, restart on
failure, and respond to `systemctl status`, wrap it in a user systemd unit.

The unit below runs the `opencode-containment:latest` image directly with
`podman run`, publishes port 17096 to the LAN, and mounts `~/github` at
`/workspace`. It is intentionally explicit (no launcher indirection) so
systemd owns the lifecycle.

```ini
# ~/.config/systemd/user/opencode-web-container.service
[Unit]
Description=OpenCode Web Server (Podman container)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h/github
Environment=HOME=%h
Environment=PATH=/usr/local/bin:/usr/bin:/bin

ExecStart=/usr/bin/podman run --replace \
  --name opencode-web-container \
  --userns keep-id \
  --user 1000:1000 \
  --cap-drop=ALL \
  --security-opt no-new-privileges:true \
  --read-only \
  --init \
  --tmpfs /tmp:rw,nosuid,nodev,exec,size=256m \
  --tmpfs /home/opencode/.config:rw,nosuid,nodev,noexec,size=16m \
  --workdir /workspace \
  --env HOME=/home/opencode \
  --env XDG_CONFIG_HOME=/home/opencode/.config \
  --env XDG_DATA_HOME=/home/opencode/.local/share \
  --env XDG_CACHE_HOME=/home/opencode/.cache \
  --env XDG_STATE_HOME=/home/opencode/.local/state \
  --env OPENCODE_SERVER_PASSWORD=changeme \
  -v %h/github:/workspace:rw,Z \
  -v %h/.config/opencode:/home/opencode/.config/opencode:ro,Z \
  -v %h/.local/share/opencode-container/local:/home/opencode/.local:rw,Z \
  -v %h/.local/share/opencode-container/cache:/home/opencode/.cache:rw,Z \
  -v %h/.gitconfig:/home/opencode/.gitconfig:ro,Z \
  -v %h/.ssh/config:/home/opencode/.ssh/config:ro,Z \
  -v %h/.ssh/known_hosts:/home/opencode/.ssh/known_hosts:ro,Z \
  -p 0.0.0.0:17096:17096 \
  --entrypoint /bin/sh \
  localhost/opencode-containment:latest \
  -c 'exec opencode web --hostname 0.0.0.0 --port 17096'

ExecStop=/usr/bin/podman stop -t 10 opencode-web-container
ExecStopPost=/usr/bin/podman rm -f opencode-web-container
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

Notes:

- `--replace` lets systemd restart the service cleanly; a stale container
  with the same name is removed on start.
- `:Z` relabeling is required on SELinux-Enforcing hosts. Omit it on
  non-SELinux systems if you hit label errors.
- The host OpenCode config directory is mounted read-only so the container
  sees the same `opencode.json`, agents, skills, and commands as the host.
- Container state (`~/.local`, `~/.cache`) is isolated under
  `~/.local/share/opencode-container/` so container sessions do not collide
  with host OpenCode sessions. Run `make sync-config` (or
  `opencode-container --sync-config`) once before enabling the service so
  auth and cache are seeded.
- `OPENCODE_SERVER_PASSWORD` is required for network exposure. Set a strong
  password. The username defaults to `opencode`; override with
  `OPENCODE_SERVER_USERNAME` if needed.
- The service is a **user** unit. Enable lingering (`loginctl enable-linger
  $USER`) if you want it to start at boot before you log in.

Manage it with:

```bash
systemctl --user daemon-reload
systemctl --user enable --now opencode-web-container
systemctl --user status   opencode-web-container
systemctl --user restart  opencode-web-container
journalctl --user -u opencode-web-container -f
```

## Attaching a TUI to a running web server

Use the **host** `opencode` binary to attach a local TUI to the running web
server. Do not use `opencode-container` for the attach step: the launcher
starts a new container and runs `opencode` inside it, which is not the same as
attaching your local TUI to a remote server.

```bash
opencode attach http://192.168.0.200:17096 --dir /workspace/percolate
```

### Path translation

The container mounts your workspace at `/workspace`, not at the host path.
Inside the container, `opencode web` only sees `/workspace/<project>`. When
you attach from the host, `--dir` is sent to the server verbatim, so you must
use the **container path**:

| Host path | Container path |
|-----------|----------------|
| `~/github/percolate` | `/workspace/percolate` |
| `~/github/opencode-containment` | `/workspace/opencode-containment` |

`~` expands on the **client** (host) side to `/home/$USER/...`, which the
container cannot see. Use `/workspace/...` for any `--dir` value sent to a
containerized server.

### HTTP, not HTTPS

`opencode web` serves plain HTTP. Use `http://`, not `https://`. If you need
TLS, put a reverse proxy (Caddy, nginx, etc.) in front of the container port.

### Native (non-container) server

If you also run a native `opencode web` on the host (no container), use the
host path and the native port:

```bash
opencode attach http://192.168.0.50:7096 --dir ~/github/percolate
```

The native server sees host paths directly, so `~/github/...` works there.