# Security Report

## Purpose

The goal of this project is to reduce the blast radius of developer and agentic processes by adding isolation and boundaries around the interactive harness itself.

This project is not an agent permission or policy system. Agent permissions, model/tool configuration, and approval rules are handled elsewhere. The focus here is runtime containment for a human-operated development workflow: preserve the normal interactive experience while reducing unnecessary access to the host, credentials, and filesystem state where practical.

This is a public repository. Do not commit secrets, tokens, or personal configuration. The `opencode-local.sh` override file is gitignored specifically to keep personal config local.

## Usability First

If this environment is too restrictive, developers will not use it.

This project intentionally aims for a practical middle ground:
- reduce accidental host damage
- reduce direct write access to sensitive host config
- keep the main developer workflow working

It is a risk-reduction wrapper, not a perfect sandbox.

## Threat Model

The core threat this project addresses is **indirect prompt injection**: hidden instructions embedded in repository files that trick agents into exfiltrating data or performing unsafe operations.

The included `demo/` directory demonstrates this with real attack vectors:

| File | Vector | Why it works |
|------|--------|---------------|
| `README.md` | Hidden HTML comment | Invisible in rendered markdown |
| `src/app.py` | Code comment | Looks like CI/CD policy |
| `.github/copilot-instructions.md` | Rules file | Models treat this as authoritative |
| `TODO.md` | Hidden comment | Alternate exfiltration path |

Models tested resist **direct** exfiltration requests but follow **indirect** instructions embedded in files they read. Containment helps even when the model does not resist: the default container profile blocks access to host secrets (`~/.ssh`, `~/.aws`, and similar paths) because those paths are never mounted.

Running with `--network none` blocks exfiltration entirely, but also prevents the agent from doing useful work. The launcher has no built-in `--no-network` flag; `--network none` must be added manually via `DOCKER_ARGS+=(--network none)` in `opencode-local.sh`. This tradeoff is the core tension the project addresses: reduce the blast radius when an agent follows malicious instructions hidden in repository files, without breaking the workflows developers need.

## Two Backends

This project ships two backends rather than forcing one choice:

- **`container` backend** (`make run`, `bin/opencode-container`): Runs against a local Docker image you build. Keeps the host integration knobs (local overrides, custom mounts) and is the best fit for daily SSH + tmux + neovim workflows (tmux runs on the host; the image includes neovim but not tmux). Isolation is provided by a hardened container (read-only root, dropped capabilities, no-new-privileges, tmpfs /tmp, `--init`).

- **`sandbox` backend** (`make run-sandbox`, `bin/opencode-sandbox`): Uses Docker Sandboxes (`sbx`), which runs the agent inside a lightweight microVM. This provides kernel-level separation beyond what a Linux container can offer. Host OpenCode config is mounted read-only and host auth is copied into a sandbox-specific read-only auth mirror. Sandbox sessions and `opencode.db` remain sandbox-local, so native, container, and sandbox usage do not overwrite each other's session databases. Network policy is managed via `config/sbx-network-allow.txt` and applied with `make setup-sandbox-policy`. Trades the local-override flexibility of the container backend for a cleaner runtime boundary.

Both backends share the same workspace guardrails (blocks `/`, `$HOME`, and out-of-tree mounts) and the same profile model (`secure` / `native`). Use `make run` for daily work; use `make run-sandbox` when you want stronger isolation or are running untrusted agent code.

## Security Controls

### Container Backend Controls

| Control | Status | How it's enforced |
|---------|--------|-------------------|
| `--cap-drop=ALL` | Active | All Linux capabilities dropped |
| `--security-opt no-new-privileges:true` | Active | Prevents privilege escalation via setuid binaries |
| `--read-only` | Active | Root filesystem is read-only |
| `--tmpfs /tmp` | Active | Ephemeral tmpfs, 256MB, nosuid/nodev |
| `--init` | Active | Init process (tini) for signal handling and zombie reaping |
| `--user $(id -u):$(id -g)` | Active | Non-root user mapping |
| `--rm` | Active | Container removed on exit |
| Workspace guardrails | Active | Rejects `/`, `$HOME`, and out-of-tree mounts |
| Host config mounts | Read-only | `.gitconfig`, `.ssh/config`, `.ssh/known_hosts`, OpenCode config, GitHub CLI config |
| SSH keys | Not mounted | SSH agent socket forwarded instead |
| Docker socket | Not mounted | `/var/run/docker.sock` never exposed |
| Seccomp | Active | Docker default seccomp profile filters syscalls |
| AppArmor | Runtime default | Applied by Docker runtime default, not explicitly pinned by the launcher |

### Sandbox Backend Controls

| Control | Status | How it's enforced |
|---------|--------|-------------------|
| MicroVM isolation | Active | `sbx` runs the agent inside a lightweight VM with kernel-level separation |
| Memory limit | Active | `--memory` passed to `sbx` (default: `8g`) |
| CPU limit | Active | `--cpus` passed to `sbx` (default: `4`) |
| Workspace guardrails | Active | Same checks as container backend |
| Host OpenCode config | Read-only | Mounted read-only into sandbox |
| Host auth | Read-only mirror | Copied to auth mirror, symlinked read-only inside sandbox |
| Sandbox sessions | Sandbox-local | `opencode.db` not seeded from host; sessions stay isolated |
| Network policy | Configurable | `config/sbx-network-allow.txt` + `make setup-sandbox-policy` |

## What This Mitigates

| Area | Status | Why it helps |
|------|--------|--------------|
| Read-only container root filesystem | Mitigated | Prevents most writes outside approved writable paths. |
| Unsafe broad mounts | Mitigated | Blocks mounting `/`, `$HOME`, or paths outside the current tree. |
| Host config tampering | Mitigated | Git, SSH, OpenCode, and GitHub config are mounted read-only. |
| Direct host SSH key exposure | Mitigated | Uses forwarded SSH agent instead of mounting private keys. |
| Privilege escalation inside container | Mitigated | Drops capabilities and blocks privilege escalation. |
| Zombie processes and signal handling | Mitigated | `--init` runs an init process (tini) inside the container. |
| Broad env leakage | Partially mitigated | Only selected variables are passed through (`GITHUB_TOKEN`, `GH_TOKEN`, proxy vars, `NODE_EXTRA_CA_CERTS`). |
| Host state separation | Partially mitigated | Container state/cache is kept under a dedicated host directory. |
| Stronger runtime isolation (sandbox backend) | Mitigated | Docker Sandboxes runs the agent inside a microVM, providing kernel-level separation beyond what a container can offer. |

## Known Accepted Risks

| Area | Status | Why kept |
|------|--------|----------|
| Read-write workspace mount | Accepted | Developers need to edit code and persist changes. |
| SSH agent forwarding | Accepted | Needed for normal Git/SSH workflows. |
| GitHub auth/config access | Accepted | Needed for PR and repo workflows. |
| Open internet access | Accepted | Needed for package installs, search, web fetch, and normal development. |
| Mirrored OpenCode auth by default | Accepted | Keeps native, container, and sandbox usage simple without sharing private SSH keys. |
| Persistent container state/cache | Accepted | Avoids repeated setup and re-login on every run. |
| Optional secure mode remains available | Accepted | Kept as a lower-integration fallback, but not made the main path to avoid adoption friction. |
| Sandbox backend provides stronger isolation | Accepted | Available via `make run-sandbox`; adds microVM boundary for agents that need it. |
| Resource limits (container backend) | Accepted | The container backend does not set explicit memory, CPU, or PID limits (the sandbox backend does via `sbx --memory` and `--cpus`). This avoids over-constraining diverse workloads. Add limits in `opencode-local.sh` via `DOCKER_ARGS+=(--memory 4g --cpus 2 --pids-limit 512)` if needed. |
| XDG state seeding from host | Accepted | Host OpenCode auth (`auth.json`, `account.json`, `mcp-auth.json`) is copied into container state each launch. `opencode.db` is seeded only on first init to preserve container-created sessions. Cache and state files (plugins, `models.json`, `plugin-meta.json`) are seeded first-init. `plugin-meta.json` host paths are rewritten to container home paths. This is accepted to keep the native workflow smooth without re-login. |

## Not Fully Solved

| Area | Status | Note |
|------|--------|------|
| Exfiltration prevention | Not fully addressed | Network access remains usable by default. Add `DOCKER_ARGS+=(--network none)` in `opencode-local.sh` for offline/audit mode. |
| Malicious repo changes | Not prevented | The workspace is intentionally writable. |
| Credential misuse by a rogue agent | Not prevented | Some credentials are intentionally available for real workflows. |
| Full isolation | Not provided | Docker reduces risk, but this is not a complete security boundary. |
| Stronger isolation (microVM) | Available | Use `make run-sandbox` for Docker Sandboxes-backed isolation. |
| AppArmor pinning | Not provided | AppArmor is applied only when the Docker runtime's default profile is active. On hosts without AppArmor, the launcher does not pin an explicit profile. Pin it in `opencode-local.sh` with `DOCKER_ARGS+=(--security-opt apparmor=docker-default)` if your runtime supports it. |
| `opencode-local.sh` can defeat containment | Accepted | The local override hook can add unsafe mounts, privileges, or credentials. This is the same tradeoff Distrobox makes. Documented forbidden patterns; cannot enforce programmatically without removing the hook entirely, which kills usability. |

## Vulnerability Scanning

GitHub Actions CI builds the image and scans it with Trivy, focusing on CRITICAL and HIGH severity findings. Results are uploaded to GitHub Code Scanning. This catches known vulnerabilities in the base image and installed packages at build time, but it is a point-in-time scan, not continuous monitoring of a running environment.

## Why We Did Not Remove More

- We did not make the workspace read-only because that would break normal development.
- We did not remove SSH, GitHub access, or OpenCode auth because many real workflows need them.
- We did not block normal internet access by default because that adds too much friction.
- We avoided adding many security profiles because complexity reduces adoption.
- We kept one main recommended workflow and one optional lower-integration mode because that is simpler to explain and use.

## Bottom Line

This setup meaningfully reduces some host-level risk, especially accidental damage and unnecessary host write access.

It does **not** claim to fully stop a determined rogue agent from changing repo contents, using allowed credentials, or sending data over allowed network paths.

Use it as a practical safety layer, not as a complete isolation boundary.