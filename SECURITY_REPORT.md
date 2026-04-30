# Security Report

## Usability First

If this environment is too restrictive, developers will not use it.

This project intentionally aims for a practical middle ground:
- reduce accidental host damage
- reduce direct write access to sensitive host config
- keep the main developer workflow working

It is a risk-reduction wrapper, not a perfect sandbox.

## What This Mitigates

| Area | Status | Why it helps |
| --- | --- | --- |
| Read-only container root filesystem | Mitigated | Prevents most writes outside approved writable paths. |
| Unsafe broad mounts | Mitigated | Blocks mounting `/`, `$HOME`, or paths outside the current tree. |
| Host config tampering | Mitigated | Git, SSH, OpenCode, and GitHub config are mounted read-only. |
| Direct host SSH key exposure | Mitigated | Uses forwarded SSH agent instead of mounting private keys. |
| Privilege escalation inside container | Mitigated | Drops capabilities and blocks privilege escalation. |
| Broad env leakage | Partially mitigated | Only selected variables are passed through. |
| Host state separation | Partially mitigated | Container state/cache is kept under a dedicated host directory. |
| Stronger runtime isolation (sandbox backend) | Mitigated | Docker Sandboxes runs the agent inside a microVM, providing kernel-level separation beyond what a container can offer. |

## Known Accepted Risks

| Area | Status | Why kept |
| --- | --- | --- |
| Read-write workspace mount | Accepted | Developers need to edit code and persist changes. |
| SSH agent forwarding | Accepted | Needed for normal Git/SSH workflows. |
| GitHub auth/config access | Accepted | Needed for PR and repo workflows. |
| Open internet access | Accepted | Needed for package installs, search, web fetch, and normal development. |
| Mirrored OpenCode auth by default | Accepted | Keeps host and container usage simple. |
| Persistent container state/cache | Accepted | Avoids repeated setup and re-login on every run. |
| Optional secure mode remains available | Accepted | Kept as a lower-integration fallback, but not made the main path to avoid adoption friction. |
| Sandbox backend provides stronger isolation | Accepted | Available via `make run-sandbox`; adds microVM boundary for agents that need it. |

## Not Fully Solved

| Area | Status | Note |
| --- | --- | --- |
| Exfiltration prevention | Not fully addressed | Network access remains usable by default. |
| Malicious repo changes | Not prevented | The workspace is intentionally writable. |
| Credential misuse by a rogue agent | Not prevented | Some credentials are intentionally available for real workflows. |
| Full isolation | Not provided | Docker reduces risk, but this is not a complete security boundary. |
| Stronger isolation (microVM) | Available | Use `make run-sandbox` for Docker Sandboxes-backed isolation. |

## Two Backends

This project ships two backends rather than forcing one choice:

- **`container` backend** (`make run`, `bin/opencode-container`): Runs against a local Docker image you build. Keeps the host integration knobs (local overrides, custom mounts) and is the best fit for daily SSH + tmux + neovim workflows. Isolation is provided by a hardened container (read-only root, dropped capabilities, no-new-privileges, tmpfs /tmp).

- **`sandbox` backend** (`make run-sandbox`, `bin/opencode-sandbox`): Runs against Docker Sandboxes (`sbx`), which executes the agent inside a lightweight microVM. This provides kernel-level separation beyond what a Linux container can offer. Trades the local-override flexibility of the container backend for a cleaner runtime boundary.

Both backends share the same workspace guardrails (blocks `/`, `$HOME`, and out-of-tree mounts) and the same profile model (`secure` / `native`). Use `make run` for daily work; use `make run-sandbox` when you want stronger isolation or are running untrusted agent code.

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
