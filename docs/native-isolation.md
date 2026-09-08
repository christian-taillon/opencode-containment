# Native Isolation by Harness and Operating System

This reference documents what each coding-agent harness does **without Docker or Docker Sandboxes**.

Organized by harness first, then operating system.

Verified against current vendor documentation and source on **2026-09-07**.

## Rating key

| Label | Meaning |
|---|---|
| **Strong native sandbox** | OS-enforced filesystem/process/network restrictions are a first-class harness feature |
| **Partial / evolving** | Real OS-backed enforcement exists, but support or behavior is still platform-specific or less mature |
| **Permissions only** | Harness can gate tools/actions, but commands still execute with the user's normal OS authority |
| **External boundary recommended** | Use Docker, Docker Sandboxes, a VM, or another OS isolation layer when you need real containment |

---

# Claude Code

Claude Code has a genuine native sandbox feature. Anthropic documents the sandbox as OS-backed rather than merely approval-based.

## macOS

**Status: Strong native sandbox**

Claude Code uses Apple's sandboxing facilities to restrict command execution. Anthropic describes macOS sandboxing as using the operating system's native sandbox mechanism.

Practical implications:

- filesystem access can be constrained around the working directory and explicitly allowed paths;
- network access is mediated according to sandbox configuration;
- sandboxed commands can be auto-approved separately from commands that would escape the sandbox;
- the harness still has an approval system on top of the OS boundary.

Use `/sandbox` in Claude Code to inspect or configure sandbox behavior.

## Linux

**Status: Strong native sandbox**

Claude Code uses **bubblewrap (`bwrap`)** for Linux sandboxing. Bubblewrap creates Linux namespaces and mount boundaries so commands can receive a restricted filesystem view instead of simply inheriting the user's entire filesystem.

Anthropic's sandbox configuration also covers network policy and filesystem allow/deny behavior.

Important operational note: when Claude Code itself runs inside another restricted container, its inner `bwrap` sandbox may fail if user namespaces or required namespace operations are blocked. If Docker or a microVM is already your primary boundary, test whether keeping Claude's nested sandbox enabled adds value or only breaks tooling.

## Windows native

**Status: No equivalent first-class native sandbox documented; external boundary recommended**

Claude Code supports Windows, but Anthropic's documented native sandbox implementation is centered on macOS and Linux mechanisms. Do not assume PowerShell approval prompts provide the same containment as macOS Seatbelt-style enforcement or Linux bubblewrap.

For strong isolation on Windows, prefer one of:

- Docker Sandboxes from Windows 11;
- WSL2 plus Claude Code's Linux sandbox;
- a development VM.

## WSL2

**Status: Strong native sandbox via Linux path, subject to WSL/kernel capabilities**

Run Claude Code inside WSL2 and treat it as the Linux implementation. Bubblewrap/user namespaces must be available.

Remember that Windows files mounted into WSL under `/mnt/c`, `/mnt/d`, and similar paths are still potentially reachable if your sandbox policy permits them. WSL itself is not a per-project filesystem allowlist.

## Recommended Claude posture

- macOS: native sandbox is a strong low-friction default.
- Linux: native sandbox is a strong low-friction default when `bwrap` works correctly.
- Windows: prefer WSL2 or an external container/microVM boundary.
- Untrusted repositories/high autonomy: Docker Sandboxes `--clone` provides a cleaner whole-environment boundary than relying only on the harness sandbox.

Official reference: <https://code.claude.com/docs/en/sandboxing>

---

# OpenAI Codex CLI

Codex has one of the more sophisticated cross-platform native sandbox implementations. The exact backend differs by operating system.

Codex separates two concepts:

- **approval policy**: when the model must ask before an action;
- **sandbox policy**: what the OS actually allows the resulting process to access.

Typical modes include read-only, workspace-write, and unrestricted/full-access behavior. Network access is separately controllable for workspace-write configurations.

## macOS

**Status: Strong native sandbox**

Codex uses Apple's **Seatbelt** sandbox through `/usr/bin/sandbox-exec`.

OpenAI's Codex source constructs Seatbelt profiles that constrain filesystem access and network behavior according to the selected permission/sandbox profile. In workspace-write mode, configured writable roots are opened while protected areas can remain read-only.

This is real OS enforcement, not just a model instruction.

## Linux

**Status: Strong native sandbox**

Current Codex source uses **bubblewrap as the default Linux filesystem sandbox**.

The current implementation:

- uses the first trusted `bwrap` found on `PATH`, with a bundled fallback;
- mounts `/` read-only by default;
- selectively bind-mounts permitted writable roots;
- can re-protect subpaths such as `.git` and `.codex` as read-only;
- creates user and PID namespaces;
- can create a separate network namespace when network is restricted;
- applies `PR_SET_NO_NEW_PRIVS`;
- applies seccomp network filtering;
- supports managed proxy routing for narrower network access.

Codex also retains a **legacy Landlock + mount protections** backend, selectable with `features.use_legacy_landlock = true` when compatible with the requested policy.

This is meaningfully stronger than a simple "only ask before shell commands" permission model.

## Windows native

**Status: Partial/evolving but real OS-backed sandbox**

Codex includes a dedicated Windows sandbox implementation rather than treating Windows as approval-only.

Current source includes:

- dedicated sandbox users/principals;
- ACL-based filesystem controls;
- explicit read/write roots and deny-read handling;
- Windows Filtering Platform (WFP) network rules;
- separate online/offline sandbox identities;
- setup/doctor flows for provisioning and validation;
- an elevated sandbox setup path.

The implementation is substantial, but Windows behavior has historically evolved more quickly than macOS/Linux. Use `codex doctor` / sandbox diagnostics on Windows and keep Codex current rather than assuming parity with the Linux or macOS backend.

## WSL2

**Status: Strong native sandbox via Linux bubblewrap path**

OpenAI's source explicitly documents **WSL2 using the normal Linux bubblewrap path**.

WSL1 is not supported for that sandbox path because it cannot create the required user namespaces. Codex rejects sandboxed shell commands that would require bubblewrap under WSL1.

## Recommended Codex posture

- macOS: native sandbox is strong and appropriate for routine use.
- Linux: native bubblewrap sandbox is strong and feature-rich.
- Windows: native sandbox is real, but verify its doctor/setup state and keep current.
- WSL2: prefer the normal Linux sandbox path over WSL1.
- Untrusted repos/high autonomy: an outer Docker Sandbox microVM can still reduce exposure beyond the harness process itself.

Official/security reference: <https://developers.openai.com/codex/security>

Implementation references:

- Linux sandbox: <https://github.com/openai/codex/tree/main/codex-rs/linux-sandbox>
- macOS Seatbelt implementation: <https://github.com/openai/codex/blob/main/codex-rs/sandboxing/src/seatbelt.rs>
- Windows sandbox: <https://github.com/openai/codex/tree/main/codex-rs/windows-sandbox-rs>

---

# OpenCode

OpenCode's built-in security model is primarily a **tool permission system**, not a general OS sandbox.

Current OpenCode V2 permission documentation explicitly warns that shell execution runs with the same operating-system authority as the user launching OpenCode. A deny/ask rule can stop OpenCode from invoking a command, but once a shell command is allowed, the child process is not automatically placed into a separate filesystem/network/process sandbox.

That distinction matters more than the operating system here.

## macOS

**Status: Permissions only; external boundary recommended for containment**

OpenCode can allow, ask, or deny tools and command patterns, but allowed commands inherit the user's macOS authority.

There is no documented OpenCode-native equivalent to Codex's Seatbelt profile or Claude's native sandbox layer.

If you need runtime containment, use:

- Docker Sandboxes;
- a Docker/Podman container;
- a VM;
- an independently configured macOS sandboxing wrapper.

## Linux

**Status: Permissions only; external boundary recommended for containment**

OpenCode's permission rules are useful guardrails, but allowed shell commands are not automatically confined with bubblewrap, Landlock, namespaces, seccomp, or a similar OpenCode-owned native sandbox.

This is the main motivation for this repository's `opencode-container` and `opencode-sandbox` launchers.

The project adds an external boundary around OpenCode while preserving normal terminal workflows.

## Windows native

**Status: Permissions only; external boundary recommended for containment**

OpenCode permission rules do not create a Windows AppContainer/restricted-token/WFP-style runtime sandbox for approved commands.

Use Docker Sandboxes, WSL2 plus an external Linux boundary, or a VM if you need strong containment.

## WSL2

**Status: Permissions only inside the WSL Linux environment**

Running OpenCode in WSL2 changes the host environment but does not itself give OpenCode a per-project native sandbox. An approved command can reach whatever the WSL user can reach, including Windows mounts if available.

Use Docker/Podman, Docker Sandboxes, bubblewrap/firejail, or another explicit Linux isolation layer if you want a stronger runtime boundary.

## Recommended OpenCode posture

- Treat permission rules as useful **policy**, not containment.
- For daily Linux/macOS use, a narrow container is a practical boundary.
- For stronger isolation and unfamiliar repositories, use Docker Sandboxes.
- For a tuned OpenCode-specific implementation, use this repository's `opencode-container` and `opencode-sandbox` launchers.

Official permission reference: <https://opencode.ai/v2/docs/permissions>

---

# Cursor CLI

Cursor has native sandbox/run-mode controls in addition to approval behavior. The exact implementation and maturity vary by platform and product surface.

Cursor's security model distinguishes sandboxed execution modes from broader agent modes. Its sandbox configuration can control filesystem and network behavior around commands the agent runs.

## macOS

**Status: Strong/partial native sandbox depending on selected Cursor run mode**

Cursor documents a sandboxed agent execution mode on macOS with filesystem/network restrictions rather than merely a confirmation prompt.

Use Cursor's sandbox/run-mode configuration when you want commands constrained to the workspace and approved external resources.

Because Cursor's CLI and editor-agent surfaces evolve rapidly, confirm the active run mode rather than assuming every agent invocation is sandboxed identically.

## Linux

**Status: Strong/partial native sandbox depending on selected Cursor run mode**

Cursor documents Linux sandbox support using OS-level controls around agent command execution. Current documentation references sandbox configuration and Linux-specific enforcement/status behavior.

As with Claude/Codex, nested Linux sandboxing may interact poorly with an already restrictive Docker container if required namespaces are unavailable.

## Windows native

**Status: Platform support should be verified for the active Cursor CLI/run mode**

Cursor supports Windows as a product, but do not infer that every Windows CLI or editor agent mode has identical native sandbox enforcement to macOS/Linux.

For a security-sensitive workflow where the exact Windows native sandbox backend is unclear, use Docker Sandboxes or WSL2 plus an explicitly verified Linux sandbox.

## WSL2

**Status: Linux path when the CLI is actually running inside WSL2**

If the Cursor CLI is installed and executed inside WSL2, evaluate it as a Linux process and verify the active sandbox/run mode there.

Windows-mounted paths remain part of the reachable filesystem unless restricted by the sandbox policy.

## Recommended Cursor posture

- Verify the active run mode before relying on native containment.
- Prefer the sandboxed run mode where available.
- For cross-platform consistency or untrusted repositories, Docker Sandboxes gives you a clearer microVM boundary independent of Cursor's internal implementation.

Official references:

- Run modes: <https://cursor.com/docs/agent/security/run-modes>
- Sandbox reference: <https://cursor.com/docs/reference/sandbox>

---

# Cross-harness summary

| Harness | macOS | Linux | Windows native | WSL2 |
|---|---|---|---|---|
| **Claude Code** | Strong native sandbox | Strong native sandbox (`bwrap`) | External boundary preferred | Linux sandbox path |
| **Codex CLI** | Strong Seatbelt sandbox | Strong `bwrap` + seccomp; legacy Landlock available | Real native Windows sandbox, evolving | Normal Linux `bwrap` path |
| **OpenCode** | Permissions only | Permissions only | Permissions only | Permissions only |
| **Cursor CLI** | Native sandbox/run modes available | Native sandbox/run modes available | Verify active platform/run-mode support | Linux path when run in WSL2 |

## Practical ranking for native-only use

For users who do **not** want an external container/VM boundary:

1. **Codex**: strongest documented cross-platform native isolation story, especially Linux/macOS.
2. **Claude Code**: strong macOS/Linux native sandboxing; Windows is better approached through WSL2 or external isolation.
3. **Cursor**: meaningful native sandboxing, but verify the active product/run mode and platform behavior.
4. **OpenCode**: permissions are useful, but they should not be presented as OS containment.

This ranking is about **native runtime isolation only**, not model quality, usability, permissions UX, or overall product security.

---

# Native sandbox vs container vs microVM

| Boundary | Protects against | Does not automatically protect against |
|---|---|---|
| Harness approvals | accidental/disallowed tool use | an allowed process using the user's full authority |
| Harness native sandbox | filesystem/network/process access outside policy | vulnerabilities in the host kernel or sandbox implementation; deliberately allowed workspace damage |
| Docker/Podman container | broad host filesystem/process separation | shared-kernel escape risk; damage to RW mounts |
| Docker Sandbox microVM | stronger kernel boundary and isolated environment | damage to intentionally shared RW workspace; misuse of intentionally injected credentials |

The safest useful configuration is usually not "maximum restrictions everywhere." It is a **clear primary boundary** plus narrow explicit access:

```text
workspace -> only what the agent needs
credentials -> only what the provider needs
network -> only what the task needs
host -> otherwise absent
```

For a simple cross-harness implementation, start with [`cli-containment-cheat-sheet.md`](cli-containment-cheat-sheet.md).
