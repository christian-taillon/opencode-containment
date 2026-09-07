# AI Coding CLI Containment Cheat Sheet

Docker-first, copy/paste containment for **Claude Code**, **OpenAI Codex CLI**, **OpenCode**, and **Cursor CLI**.

This is intentionally simpler than the full `opencode-containment` launcher. The goal is to answer one question quickly:

> How do I run an AI coding CLI against only the current project, keep its login/config persistent, and make network access explicit?

Verified against current vendor documentation on 2026-09-07.

## The basic containment model

Keep the boundary small:

- Current directory only -> mounted read-write at `/workspace`.
- CLI state only -> persisted under a private host state directory.
- Do **not** mount `$HOME`, `/`, private SSH keys, `.env` collections, or the Docker socket.
- Docker's normal bridge network -> outbound Internet available.
- `--network none` -> no network at all.
- The workspace remains writable, so the agent can still modify or delete project files.

Docker is useful containment, but it is not a VM. The container still shares the host kernel.

## Client OS

These examples use a POSIX shell and are intended for:

| Client OS | Recommended path | Notes |
|---|---|---|
| Linux | Docker Engine + Bash/Zsh | Native path. On SELinux hosts, add `:Z` to bind mounts. |
| macOS | Docker Desktop/OrbStack + Bash/Zsh | Works with normal `$PWD` bind mounts if the directory is shared with Docker. |
| Windows | WSL2 + Docker Desktop | Recommended for this sheet. Run the Linux commands from WSL. |
| Windows native PowerShell | Not covered yet | Path quoting, UID handling, and TTY syntax differ. |

The container itself is Linux even when the client is macOS or Windows.

## Network switch

### Internet available

Use Docker's default network. No extra network flag is required:

```bash
docker run ...
```

This allows normal provider API calls, package installation, Git fetches, web requests, and arbitrary outbound traffic permitted by the host/network.

### No network

Add:

```bash
--network none
```

Example:

```bash
docker run --network none ...
```

Important: a cloud coding agent cannot call its model provider with `--network none`. This mode is mainly useful for offline inspection, testing the containment boundary, or a CLI/model that is already available inside the same container.

## Common state directory

The examples below keep container-only credentials and config under:

```bash
${XDG_DATA_HOME:-$HOME/.local/share}/ai-cli-containment/
```

That avoids sharing the host CLI's normal credential store with the container.

Treat these directories as secrets. They can contain refresh tokens and provider credentials.

---

## OpenCode

OpenCode publishes an official image:

```text
ghcr.io/anomalyco/opencode
```

OpenCode stores global config under `~/.config/opencode` and provider credentials under `~/.local/share/opencode/auth.json`. The command below relocates those XDG paths into isolated persistent state.

### Run with Internet

```bash
STATE="${XDG_DATA_HOME:-$HOME/.local/share}/ai-cli-containment/opencode"; \
mkdir -p "$STATE" && chmod 700 "$STATE" && \
docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -e HOME=/state/home \
  -e XDG_CONFIG_HOME=/state/config \
  -e XDG_DATA_HOME=/state/data \
  -e XDG_CACHE_HOME=/state/cache \
  -v "$STATE:/state" \
  -v "$PWD:/workspace" \
  -w /workspace \
  ghcr.io/anomalyco/opencode
```

Log in once inside the contained environment:

```bash
opencode auth login
```

The login persists in `$STATE` across disposable containers.

### No network

Use the same command and add:

```bash
--network none
```

---

## Claude Code

Anthropic documents npm installation for Claude Code, so a stock Node Linux image is enough for a minimal disposable container. The CLI installation itself is cached in the same isolated state directory after the first run.

Claude Code supports `CLAUDE_CONFIG_DIR`; on Linux its credential file normally lives under the Claude config directory.

### Run with Internet

```bash
STATE="${XDG_DATA_HOME:-$HOME/.local/share}/ai-cli-containment/claude"; \
mkdir -p "$STATE" && chmod 700 "$STATE" && \
docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -e HOME=/state/home \
  -e CLAUDE_CONFIG_DIR=/state/claude \
  -e NPM_CONFIG_PREFIX=/state/npm \
  -e PATH=/state/npm/bin:/usr/local/bin:/usr/bin:/bin \
  -v "$STATE:/state" \
  -v "$PWD:/workspace" \
  -w /workspace \
  node:22-bookworm \
  sh -lc 'command -v claude >/dev/null 2>&1 || npm install -g @anthropic-ai/claude-code; exec claude'
```

The first launch installs Claude Code into persistent container state. Later launches reuse it.

Authenticate inside the container:

```bash
claude auth login
```

Container/browser flows may give you a URL or code to open on the host browser and paste back into the terminal.

### No network

After the CLI has been installed at least once, add:

```bash
--network none
```

Claude Code still cannot reach Anthropic while networking is disabled.

---

## OpenAI Codex CLI

Codex can be installed from npm as `@openai/codex`.

Codex state is controlled by `CODEX_HOME`, which defaults to `~/.codex`. Authentication may use a system credential store or `CODEX_HOME/auth.json`. For a container, file-backed auth is the simplest persistent model.

### Run with Internet

```bash
STATE="${XDG_DATA_HOME:-$HOME/.local/share}/ai-cli-containment/codex"; \
mkdir -p "$STATE/codex" && chmod 700 "$STATE" && \
printf '%s\n' 'cli_auth_credentials_store = "file"' > "$STATE/codex/config.toml" && \
docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -e HOME=/state/home \
  -e CODEX_HOME=/state/codex \
  -e NPM_CONFIG_PREFIX=/state/npm \
  -e PATH=/state/npm/bin:/usr/local/bin:/usr/bin:/bin \
  -v "$STATE:/state" \
  -v "$PWD:/workspace" \
  -w /workspace \
  node:22-bookworm \
  sh -lc 'command -v codex >/dev/null 2>&1 || npm install -g @openai/codex; exec codex'
```

Authenticate once:

```bash
codex login
```

The login and Codex config remain under `$STATE/codex`.

> If you already maintain a Codex `config.toml`, do not overwrite it with the `printf` line above. Add `cli_auth_credentials_store = "file"` to your existing container-specific config instead.

### No network

After the CLI has been installed at least once, add:

```bash
--network none
```

Codex still cannot reach OpenAI while networking is disabled.

---

## Cursor CLI

Cursor documents the Linux/WSL installer:

```bash
curl https://cursor.com/install -fsS | bash
```

The CLI command is currently `agent`; `cursor-agent` may also be present as an explicit alias. Cursor global CLI config can be relocated with `CURSOR_CONFIG_DIR`.

For browser-auth persistence, this example persists the container's private home rather than mounting the host Cursor state.

### Run with Internet

```bash
STATE="${XDG_DATA_HOME:-$HOME/.local/share}/ai-cli-containment/cursor"; \
mkdir -p "$STATE/home" && chmod 700 "$STATE" && \
docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -e HOME=/state/home \
  -e CURSOR_CONFIG_DIR=/state/home/.cursor \
  -e PATH=/state/home/.local/bin:/usr/local/bin:/usr/bin:/bin \
  -v "$STATE:/state" \
  -v "$PWD:/workspace" \
  -w /workspace \
  node:22-bookworm \
  sh -lc 'command -v agent >/dev/null 2>&1 || curl https://cursor.com/install -fsS | bash; exec agent'
```

Authenticate once:

```bash
agent login
```

Check persistence with:

```bash
agent status
```

For automation, Cursor also supports `CURSOR_API_KEY`, which can be preferable to browser-auth state. Do not bake API keys into an image.

### No network

After the CLI has been installed at least once, add:

```bash
--network none
```

Cursor cannot reach its model service while networking is disabled.

---

## SELinux hosts: Fedora, RHEL, etc.

If Docker/Podman is blocked from reading the bind-mounted project or state directory, add an SELinux relabel option to each bind mount.

Example:

```bash
-v "$STATE:/state:Z" \
-v "$PWD:/workspace:Z"
```

Do not mechanically use `:Z` for shared directories that multiple unrelated containers need simultaneously; understand the relabel behavior first.

## What the agent can and cannot see

With the minimal pattern above:

| Resource | Visible to agent? |
|---|---:|
| Current project directory | Yes, read-write |
| CLI-specific persistent state | Yes |
| Rest of `$HOME` | No |
| `~/.ssh/id_*` private keys | No |
| Host `.env` files outside project | No |
| Docker socket | No |
| Host root filesystem | No |
| Internet | Yes by default; no with `--network none` |

Anything inside the current project is intentionally exposed. If the repository itself contains `.env`, secrets, kubeconfig files, private keys, or other credentials, Docker cannot protect those from the agent because they are inside the mounted workspace.

## Useful optional limits

For untrusted or highly autonomous work, consider adding resource limits:

```bash
--memory 8g \
--cpus 4 \
--pids-limit 512 \
--security-opt no-new-privileges:true
```

Do not blindly add aggressive capability/seccomp restrictions to every coding CLI. Some CLIs implement their own Linux sandboxing and namespace controls, and an outer Docker restriction can break the inner sandbox. Test hardening per client.

## Minimum safety checklist

Before launching an agent against an unfamiliar repository:

1. `git status` and commit/stash anything you care about.
2. Confirm the bind mount is only the intended project directory.
3. Confirm no host `$HOME`, Docker socket, SSH key directory, or broad secrets directory is mounted.
4. Decide whether the task actually needs Internet access.
5. Remember that persistent CLI state contains credentials even though the rest of the host is hidden.
6. Review `git diff` before accepting the agent's work.

## Docker Sandboxes: next layer

This sheet starts with ordinary Docker because it is widely available and easy to understand.

The next version should add the equivalent **Docker Sandboxes (`sbx`)** recipes. Docker Sandboxes can provide a stronger microVM boundary while keeping the same basic model:

- project directory -> explicit workspace
- provider credentials -> isolated/persistent agent state
- network -> explicit allowlist or deny policy
- client OS -> Linux/macOS/Windows support called out separately

This repository already contains an OpenCode-specific Docker Sandboxes backend in `bin/opencode-sandbox`; the cross-client sheet should build on that pattern rather than duplicate it.

## Vendor references

- OpenCode Docker/install: https://opencode.ai/docs
- OpenCode CLI auth: https://dev.opencode.ai/docs/cli
- Claude Code installation: https://code.claude.com/docs/en/installation
- Claude Code authentication: https://code.claude.com/docs/en/authentication
- Claude Code dev containers: https://code.claude.com/docs/en/devcontainer
- Codex CLI: https://developers.openai.com/codex/cli
- Codex repository: https://github.com/openai/codex
- Cursor CLI installation: https://cursor.com/docs/cli/installation
- Cursor CLI configuration: https://cursor.com/docs/cli/reference/configuration
- Cursor CLI authentication: https://cursor.com/docs/cli/reference/authentication
