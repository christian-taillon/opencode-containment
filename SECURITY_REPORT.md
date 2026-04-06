# Security Report

## Usability First

If this environment is too restrictive, developers will not use it.

This project intentionally aims for a practical middle ground:
- reduce accidental host damage
- reduce direct write access to sensitive host config
- keep normal development workflows working

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

## Known Accepted Risks

| Area | Status | Why kept |
| --- | --- | --- |
| Read-write workspace mount | Accepted | Developers need to edit code and persist changes. |
| SSH agent forwarding | Accepted | Needed for normal Git/SSH workflows. |
| GitHub auth/config access | Accepted | Needed for PR and repo workflows. |
| Open internet access | Accepted | Needed for package installs, search, web fetch, and normal development. |
| Mirrored OpenCode auth by default | Accepted | Keeps host and container usage simple. |
| Persistent container state/cache | Accepted | Avoids repeated setup and re-login on every run. |

## Not Fully Solved

| Area | Status | Note |
| --- | --- | --- |
| Exfiltration prevention | Not fully addressed | Network access remains usable by default. |
| Malicious repo changes | Not prevented | The workspace is intentionally writable. |
| Credential misuse by a rogue agent | Not prevented | Some credentials are intentionally available for real workflows. |
| Full isolation | Not provided | Docker reduces risk, but this is not a complete security boundary. |

## Why We Did Not Remove More

- We did not make the workspace read-only because that would break normal development.
- We did not remove SSH, GitHub access, or OpenCode auth because many real workflows need them.
- We did not block normal internet access by default because that adds too much friction.
- We avoided adding many security profiles because complexity reduces adoption.

## Bottom Line

This setup meaningfully reduces some host-level risk, especially accidental damage and unnecessary host write access.

It does **not** claim to fully stop a determined rogue agent from changing repo contents, using allowed credentials, or sending data over allowed network paths.

Use it as a practical safety layer, not as a complete isolation boundary.
