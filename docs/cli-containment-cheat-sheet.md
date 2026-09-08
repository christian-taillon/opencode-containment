# AI Coding Agent Containment: Quick Start

A small cheat sheet for running **Claude Code**, **OpenAI Codex**, **OpenCode**, or **Cursor CLI** with a clearer boundary around the agent.

If you only remember one rule:

> Share the project, not your machine.

This guide intentionally stays simple. For a more mature and opinionated OpenCode setup with hardened container defaults, isolated state, workspace guardrails, Docker Sandboxes support, and helper launchers, see the main [`opencode-containment`](../README.md) project.

For the differences between each harness's built-in sandboxing on macOS, Linux, Windows, and WSL2, see [`native-isolation.md`](native-isolation.md).

Verified against current vendor documentation on **2026-09-07**.

## Pick a boundary

| Approach | Best for | Isolation |
|---|---|---|
| **Docker Sandboxes (`sbx`)** | Easiest cross-agent containment | Stronger: each sandbox is a microVM with its own Linux kernel |
| **Docker container** | Portable, familiar, easy to customize | Good process/filesystem boundary, but shares the host kernel |
| **Harness-native sandbox** | Lowest friction when the harness supports it well | Varies substantially by harness and operating system |

For unfamiliar repositories or highly autonomous agents, prefer **Docker Sandboxes**, especially `--clone` mode.

---

# 1. Docker Sandboxes: simplest path

Docker Sandboxes has built-in templates for all four agents.

From the project directory:

```bash
sbx run claude
sbx run codex
sbx run cursor
sbx run opencode
```

That is the basic containment cheat sheet.

The current directory is the workspace. The rest of the agent environment runs in an isolated microVM.

## Keep the host checkout untouched

Normal `sbx run` shares the working tree read-write, so agent edits appear immediately on the host.

For a Git repository, use **clone mode** when you do not want the agent writing directly to the host checkout:

```bash
sbx run --clone claude
sbx run --clone codex
sbx run --clone cursor
sbx run --clone opencode
```

In clone mode the host repository is exposed read-only and the agent works in a private clone inside the sandbox. Fetch or push the changes you want to keep.

## Authentication

`sbx` supports host-managed credentials and provider-specific login flows. For example:

```bash
sbx secret set openai --oauth
sbx secret set anthropic
sbx secret set cursor
```

Some agents can also perform interactive OAuth on first launch. Prefer the `sbx` credential flow over mounting your normal home directory into the sandbox.

## What Docker Sandboxes isolates

Each sandbox has its own:

- Linux kernel
- process space
- filesystem outside explicitly shared workspaces
- network
- Docker daemon
- persistent sandbox state

Provider credentials can be injected by the host-side credential proxy instead of being copied into the VM.

The default direct workspace mount is still read-write. **The microVM protects the rest of the host; it does not protect files you deliberately share read-write.** Use `--clone` when that distinction matters.

## Client OS requirements

Docker Sandboxes is a separate `sbx` product. Docker Desktop or Docker Engine is not required just to use `sbx`.

| Client OS | Current documented baseline |
|---|---|
| macOS | macOS 14+ on Apple silicon |
| Windows | Windows 11 x64 with Windows Hypervisor Platform |
| Linux | Ubuntu 24.04+ x64/arm64 with KVM enabled and user access to `/dev/kvm` |
| WSL | Run `sbx` from the supported host OS rather than treating WSL itself as the sandbox boundary |

Install instructions: <https://docs.docker.com/ai/sandboxes/install/>

---

# 2. Ordinary Docker: simple and portable

If you already have an image containing the agent CLI, the containment pattern is the same for every harness:

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  AGENT_IMAGE
```

Only the current project is deliberately shared.

## No network

Add:

```bash
--network none
```

Example:

```bash
docker run --rm -it \
  --network none \
  -v "$PWD:/workspace" \
  -w /workspace \
  AGENT_IMAGE
```

This blocks the model provider too. A cloud-backed agent normally cannot function in this mode unless its model/API is reachable through some other intentionally provided path.

## Persist login and config

Do **not** solve persistence by mounting `$HOME`.

Instead, persist only the agent's own state directory, either with a Docker volume or a narrow private bind mount:

```bash
docker volume create agent-state

docker run --rm -it \
  -v "$PWD:/workspace" \
  -v agent-state:/home/agent-state \
  -w /workspace \
  AGENT_IMAGE
```

The exact config/auth path differs by harness. Keep it narrow and treat it as secret-bearing state.

## OpenCode has an official image

OpenCode publishes `ghcr.io/anomalyco/opencode`, so the minimal container form is:

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  ghcr.io/anomalyco/opencode
```

For persistent OpenCode auth/config, mount only its XDG config/data directories rather than the entire host home directory. The full `opencode-containment` launcher in this repository already handles this more carefully.

## Claude, Codex, and Cursor images

For ordinary Docker, use an image containing the CLI you want to run:

- Claude Code: Anthropic documents dev-container/container workflows and a native installer.
- Codex: install `@openai/codex` in a small development image or use your existing agent image.
- Cursor: install Cursor CLI in a development image or use Docker Sandboxes' built-in Cursor template.

The important containment controls are the same regardless of installer:

```text
project -> explicit RW mount
agent state -> explicit private persistent mount
host home -> not mounted
Docker socket -> not mounted
network -> explicit choice
```

Avoid clever `docker run` one-liners that download and reinstall an agent on every launch. A tiny reusable image is simpler to audit and faster to use.

---

# 3. What not to mount

For a normal coding task, avoid exposing:

```text
/
$HOME
~/.ssh
~/.aws
~/.kube
~/.config wholesale
/var/run/docker.sock
large secrets directories
```

If the project itself contains credentials, `.env` files, private keys, or kubeconfigs, the agent can still see them because the project is intentionally shared.

A container cannot protect a secret that you mount into the container.

---

# 4. Optional Docker hardening

These are reasonable additions when the client still works with them:

```bash
--security-opt no-new-privileges:true \
--cap-drop=ALL \
--memory 8g \
--cpus 4 \
--pids-limit 512
```

A read-only root filesystem and explicit tmpfs mounts can reduce the writable surface further.

Do not blindly stack every restriction on top of every harness. Claude, Codex, and Cursor can use their own Linux namespace/sandbox mechanisms, and an outer container can prevent an inner sandbox from creating the namespaces it expects. In that situation, decide which layer is actually your security boundary instead of weakening both accidentally.

---

# 5. Containment is not the same as approvals

Three different controls are often mixed together:

| Control | Question it answers |
|---|---|
| Agent permissions / approvals | "Should the harness let the model try this action?" |
| Native sandbox | "What can the resulting process actually reach on this OS?" |
| Container / microVM | "What part of the host exists inside the agent's execution environment at all?" |

Permission prompts are useful, but they are not a replacement for an OS-enforced boundary.

This difference is particularly important for OpenCode: its permissions can allow, ask, or deny tools, but current V2 documentation explicitly notes that shell commands execute with the host user's filesystem, process, and network authority. Use external containment when you need an actual runtime boundary.

See [`native-isolation.md`](native-isolation.md) for the harness-by-harness details.

---

# 6. Which option should I use?

### I just want a safe, simple default

```bash
sbx run --clone AGENT
```

Replace `AGENT` with `claude`, `codex`, `cursor`, or `opencode`.

### I want edits to appear immediately in my working tree

```bash
sbx run AGENT
```

### I already live in Docker

Use a normal container and expose only the project plus narrow persistent agent state.

### I use OpenCode heavily and want a tuned daily environment

Use this repository's `opencode-container` or `opencode-sandbox` launchers. They add the opinionated pieces intentionally omitted from this cheat sheet: workspace guardrails, isolated state/auth handling, host integration choices, hardening, profiles, and Docker Sandboxes support.

### I want no external runtime at all

Check the harness's native sandbox support first: [`native-isolation.md`](native-isolation.md).

---

# Vendor references

- Docker Sandboxes: <https://docs.docker.com/ai/sandboxes/>
- Docker Sandboxes usage and clone mode: <https://docs.docker.com/ai/sandboxes/usage/>
- Docker Sandboxes agents: <https://docs.docker.com/reference/cli/sbx/run/>
- Claude Code sandboxing: <https://code.claude.com/docs/en/sandboxing>
- Codex sandboxing: <https://developers.openai.com/codex/security>
- OpenCode permissions: <https://opencode.ai/v2/docs/permissions>
- OpenCode installation / Docker image: <https://opencode.ai/docs/>
- Cursor run modes: <https://cursor.com/docs/agent/security/run-modes>
- Cursor sandbox configuration: <https://cursor.com/docs/reference/sandbox>
