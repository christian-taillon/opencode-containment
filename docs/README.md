# Containment Guides

Start here if your goal is simply to reduce the blast radius of an AI coding agent.

## Simple cross-agent guide

[`cli-containment-cheat-sheet.md`](cli-containment-cheat-sheet.md)

Use this for **Claude Code, Codex, OpenCode, or Cursor**.

The short version:

```bash
sbx run --clone claude
sbx run --clone codex
sbx run --clone cursor
sbx run --clone opencode
```

Docker Sandboxes supports all four agents out of the box. Clone mode keeps the agent's working copy inside the sandbox instead of letting it directly modify the host Git checkout.

If you prefer ordinary Docker, the same guide shows the minimal pattern: expose the project, persist only narrow agent state, and do not mount the host home directory or Docker socket.

## Native isolation reference

[`native-isolation.md`](native-isolation.md)

Use this when you want to understand what the harness itself provides without an external container or microVM.

It is organized by harness, then operating system:

- Claude Code
  - macOS
  - Linux
  - Windows
  - WSL2
- OpenAI Codex CLI
  - macOS
  - Linux
  - Windows
  - WSL2
- OpenCode
  - macOS
  - Linux
  - Windows
  - WSL2
- Cursor CLI
  - macOS
  - Linux
  - Windows
  - WSL2

## Opinionated OpenCode implementation

The repository root README and launchers are the more mature OpenCode-specific implementation.

Use them when you want more than a cheat sheet:

- hardened Docker defaults
- isolated OpenCode state and auth handling
- workspace guardrails
- native-feeling SSH/tmux/neovim workflow
- explicit host integration
- Docker Sandboxes backend
- network policy support
- prompt-injection/exfiltration demonstrations

The simple guides explain the model. `opencode-containment` implements an opinionated version of it.
