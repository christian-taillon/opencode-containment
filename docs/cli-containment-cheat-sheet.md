# Containing AI Coding Agents

A practical guide to running **Claude Code**, **OpenAI Codex**, **OpenCode**, and **Cursor** with a smaller blast radius.

The goal is not to make an agent harmless. The goal is to make the boundary obvious:

> **Share the project, not your machine.**

A useful containment setup should answer four questions:

1. What files can the agent read?
2. What files can it modify?
3. What network destinations can it reach?
4. What credentials or environment variables can its processes see?

This guide starts with containers and Docker Sandboxes, then looks at the native isolation built into each harness.

For a more mature and opinionated OpenCode implementation, see [`christian-taillon/opencode-containment`](https://github.com/christian-taillon/opencode-containment). That project adds persistent state, workspace guardrails, hardened container defaults, Docker Sandboxes support, and helper launchers around the same basic containment model described here.

Verified against current vendor documentation and source on **2026-09-07**.

---

## The 60-second version

If Docker Sandboxes is available on your machine, the simplest common interface is:

```bash
sbx run claude
sbx run codex
sbx run cursor
sbx run opencode
```

If you do not want the agent editing your host checkout directly, use clone mode:

```bash
sbx run --clone claude
sbx run --clone codex
sbx run --clone cursor
sbx run --clone opencode
```

If you prefer ordinary Docker, the generic pattern is:

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  AGENT_IMAGE
```

The important part is not the exact command. It is what is **missing** from it: no `$HOME`, no `/`, no SSH key directory, and no Docker socket.

<<insert image here: from a disposable Git repository run `sbx run --clone opencode`, then show the sandbox starting and the agent working inside the cloned project>>

---

# 1. Pick the boundary

| Approach | Best for | What it gives you |
|---|---|---|
| **Docker Sandboxes (`sbx`)** | Simple cross-agent containment | MicroVM boundary, separate kernel, filesystem, processes, network, and sandbox state |
| **Docker / Podman** | Familiar and configurable development workflow | Strong filesystem/process separation, but a shared host kernel |
| **Harness-native sandbox** | Lowest-friction local use | OS-backed restrictions when the harness and platform support them |
| **Permissions / approvals** | Human control over actions | Policy, not necessarily OS containment |

The most important distinction is between **permission** and **containment**.

A permission system asks:

> Should the model be allowed to try this command?

A sandbox asks:

> If the command runs, what can the resulting process actually reach?

Those are different controls.

---

# 2. Docker Sandboxes: the simplest common approach

Docker Sandboxes supports built-in agent templates for Claude Code, Codex, Cursor, and OpenCode.

From the project directory:

```bash
sbx run claude
```

or:

```bash
sbx run codex
sbx run cursor
sbx run opencode
```

The sandbox runs in a lightweight microVM rather than as another process directly on the host.

## Direct workspace vs. clone mode

Normal `sbx run` gives the sandbox access to the current workspace. Agent edits appear in the host working tree.

That is useful for normal development, but it means the project itself is intentionally writable.

For a Git repository you do not want the agent modifying directly, use:

```bash
sbx run --clone codex
```

Clone mode gives the agent its own copy inside the sandbox while leaving the source checkout outside the normal writable surface.

A simple rule of thumb:

```text
trusted repo + normal coding        -> sbx run AGENT
unfamiliar repo + high autonomy     -> sbx run --clone AGENT
```

## Provider credentials

Docker Sandboxes has a host-side secret system for supported providers:

```bash
sbx secret set openai --oauth
sbx secret set anthropic
sbx secret set cursor
```

The useful security property is that supported service credentials can be handled by the host-side proxy instead of simply copying the real token into the sandbox.

Do not mount your entire home directory just to reuse a login.

## Client operating systems

At the time of writing, Docker documents `sbx` for:

| Client OS | General requirement |
|---|---|
| macOS | Apple silicon, macOS 14+ |
| Windows | Windows 11 x64 with Windows Hypervisor Platform |
| Linux | Ubuntu 24.04+ x64/arm64 with KVM and access to `/dev/kvm` |

The important architectural point is that the agent runs in a separate Linux microVM regardless of whether the client machine is macOS, Windows, or Linux.

---

# 3. Ordinary Docker: simple and portable

A normal Docker container is still a useful containment boundary, especially when Docker is already part of the development workflow.

The minimal pattern is:

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  AGENT_IMAGE
```

Only the current project is deliberately shared read-write.

## OpenCode example

OpenCode publishes an official image, so the basic command is particularly small:

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  ghcr.io/anomalyco/opencode
```

<<insert image here: run `docker run --rm -it -v "$PWD:/workspace" -w /workspace ghcr.io/anomalyco/opencode` and show OpenCode starting with `/workspace` as the current project>>

## Disable networking entirely

Add:

```bash
--network none
```

For example:

```bash
docker run --rm -it \
  --network none \
  -v "$PWD:/workspace" \
  -w /workspace \
  AGENT_IMAGE
```

This is a real network cutoff, but it also blocks the model provider. A cloud-backed agent generally cannot function normally in this mode.

`--network none` is therefore most useful for:

- testing the containment boundary;
- local-model workflows;
- static inspection;
- intentionally offline tasks.

## Persist agent login/config without mounting `$HOME`

Do not solve persistence with:

```bash
-v "$HOME:/home/user"
```

That largely defeats the filesystem containment you were trying to create.

Instead, persist only the harness state it actually needs:

```bash
docker volume create agent-state

docker run --rm -it \
  -v "$PWD:/workspace" \
  -v agent-state:/home/agent-state \
  -w /workspace \
  AGENT_IMAGE
```

The exact state path varies by harness. The principle does not:

```text
workspace     -> explicit read/write mount
agent state   -> explicit persistent mount
host home     -> absent
host secrets  -> absent unless deliberately injected
```

---

# 4. Passing local environment variables without opening the whole host

This is where containment often becomes ambiguous.

Local development frequently needs things such as:

```text
DATABASE_URL
REDIS_URL
API_BASE_URL
STRIPE_TEST_KEY
AWS_PROFILE
NPM_TOKEN
GITHUB_TOKEN
```

The first question should be:

> **Does the agent itself need this value, or does only the code being tested need it?**

Those are very different situations.

## Pattern A: pass an environment file directly to the agent

For ordinary Docker:

```bash
docker run --rm -it \
  --env-file "$HOME/.config/myproject/dev.env" \
  -v "$PWD:/workspace" \
  -w /workspace \
  AGENT_IMAGE
```

Docker Sandboxes 0.39.0+ supports the equivalent:

```bash
sbx run --env-file "$HOME/.config/myproject/dev.env" codex
```

or individual variables:

```bash
sbx run -e API_BASE_URL=https://dev.example.test claude
```

This is appropriate for **configuration the agent is allowed to know**.

It is not a way to hide secrets from the agent.

If a value is in the agent process environment, assume the agent or a subprocess can inspect it, print it, log it, or pass it somewhere else.

A `.env` file being gitignored does not change that.

### Good use

```text
NODE_ENV=development
API_BASE_URL=http://localhost:8080
FEATURE_FLAG_NEW_UI=true
TEST_DATABASE_NAME=myapp_agent_test
```

### Higher-risk use

```text
AWS_SECRET_ACCESS_KEY=...
PRODUCTION_DATABASE_URL=...
GITHUB_TOKEN=...
STRIPE_SECRET_KEY=...
```

If the agent truly needs a credential, use a narrowly scoped development credential rather than a production secret.

## Pattern B: mount a local env/config file read-only

Instead of copying a local file into the workspace, mount just that file:

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -v "$HOME/.config/myproject/dev.env:/run/config/dev.env:ro" \
  -w /workspace \
  AGENT_IMAGE
```

This has two useful properties:

- the agent cannot modify the host copy through that mount;
- the file does not need to live inside the project checkout.

But it is **not secret isolation** if the agent can read `/run/config/dev.env`.

Read-only means "cannot modify," not "cannot inspect."

The same caveat applies to Docker Compose secrets. Compose can make a secret available as a file under `/run/secrets/...`, which is often safer than putting it into every process environment, but any process that is allowed to read that secret file still knows the secret.

## Pattern C: keep secrets out of the agent and inject them only into the code runner

This is the better pattern when:

- the agent should edit code;
- tests or the local application require secrets;
- the agent does **not** need to know those secrets.

Run the agent container without the env file:

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  AGENT_IMAGE
```

Then run the secret-bearing test/application process separately:

```bash
docker run --rm \
  --env-file "$HOME/.config/myproject/dev.env" \
  -v "$PWD:/workspace:ro" \
  -w /workspace \
  APP_TEST_IMAGE \
  npm test
```

Now the security boundary looks like this:

```text
Agent container
  sees: source code
  does not see: local secret env file

Test/runtime container
  sees: source code + runtime secrets
  does not expose: host home
```

The human, CI runner, or a narrowly scoped helper can execute the secret-bearing test runner and return results to the agent.

Do **not** mount `/var/run/docker.sock` into the agent just so it can create the second container. Giving the agent the Docker socket is effectively giving it control over the Docker host and can collapse the containment boundary.

<<insert image here: show two terminals side by side; left runs the agent container and `env | grep DATABASE_URL` returns nothing, right runs the test container with `--env-file "$HOME/.config/myproject/dev.env"` and successfully starts the local test suite>>

## Pattern D: use credential proxying when the secret is only needed for outbound API calls

Docker Sandboxes has an experimental custom-secret proxy for services that are not already built in.

Conceptually:

```bash
sbx secret set-custom \
  --host api.example.com \
  --env API_KEY \
  --value '<secret>'
```

The sandbox receives a placeholder instead of the real value. The host-side proxy replaces that placeholder when traffic is sent to the configured host.

This is substantially better than placing the real API token into the agent's environment when the use case fits the proxy model.

For real workflows, avoid putting the secret directly on the command line because shell history may retain it. Prefer an interactive prompt, a secret manager reference, or another protected input mechanism when supported.

## A practical two-file convention

For projects that need a lot of local configuration, consider splitting environment values by trust level:

```text
.env.agent.example      committed example/schema
.env.agent              safe local configuration the agent may receive
private runtime env     outside the repo; credentials the agent should not receive
```

For example:

```text
# .env.agent
NODE_ENV=development
API_BASE_URL=http://app:8080
LOG_LEVEL=debug
```

while the real database password or cloud token stays in something like:

```text
~/.config/myproject/dev.env
```

and is injected only into the runtime/test process that needs it.

The separation is more useful than trying to build one giant `.env` file and then asking the sandbox to somehow hide selected lines from a process that already received the file.

---

# 5. Environment-variable handling differs by harness

The generic container rule remains simple:

> If you inject a real secret into the agent's process environment, treat that secret as visible to the agent.

Some harnesses add better controls on top of that.

## Claude Code

Claude Code's current sandbox can explicitly protect credential files and environment variables used by sandboxed Bash commands.

It supports two useful modes:

- `deny`: remove the environment variable from sandboxed commands;
- `mask`: expose a placeholder while a proxy substitutes the real value only for allowed outbound destinations.

That means Claude Code can support workflows where a command such as `gh`, `npm`, or an API client authenticates without the command itself receiving the real token.

This protection applies to the sandboxed Bash execution path. It should not be generalized into "Claude can never see this secret" without checking the exact tool and settings path involved.

Useful inspection command:

```text
/sandbox
```

<<insert image here: in Claude Code run `/sandbox` and capture the Mode, Overrides, Config, and Dependencies tabs showing the sandbox is active>>

## Docker Sandboxes

For ordinary non-secret configuration:

```bash
sbx run --env-file .env.agent codex
```

For supported provider/API credentials, prefer `sbx secret` so the host-side proxy can keep the real credential outside the VM where possible.

## Codex, Cursor, and OpenCode

Do not assume a normal `--env-file` or inherited shell environment is hidden merely because the harness has a sandbox.

If the local application needs a secret but the agent does not, the cleanest cross-harness pattern remains a separate runtime/test boundary rather than exposing the secret to the agent process and depending on harness-specific filtering.

---

# 6. What not to mount

For normal coding-agent work, avoid exposing these unless there is a specific reason:

```text
/
$HOME
~/.ssh
~/.aws
~/.kube
~/.config wholesale
/var/run/docker.sock
password-manager stores
large secrets directories
```

Also inspect the project itself.

If the mounted repository contains:

```text
.env
credentials.json
service-account.json
id_rsa
kubeconfig
terraform.tfstate
```

then those files are part of the agent's workspace unless another control explicitly prevents reading them.

A container cannot protect a secret that you deliberately put inside its readable workspace.

---

# 7. Optional Docker hardening

Once the basic mount boundary works, ordinary Docker can be tightened further:

```bash
--security-opt no-new-privileges:true \
--cap-drop=ALL \
--memory 8g \
--cpus 4 \
--pids-limit 512
```

A more opinionated setup can also use:

- a read-only container root filesystem;
- explicit tmpfs writable locations;
- a non-root container user;
- narrow network policy;
- read-only host config mounts;
- separate persistent agent state;
- no private SSH key mounts;
- SSH agent forwarding only when needed.

Do not blindly stack every Linux restriction on top of every harness. Claude, Codex, and Cursor may create their own namespaces or sandbox layers. A highly restricted outer container can prevent an inner sandbox from starting.

Choose a clear primary boundary and test the nested behavior rather than assuming "more sandbox flags" always means "more secure."

---

# 8. Native isolation: Claude Code

Claude Code has a genuine OS-backed sandbox for its **Bash tool**.

The distinction matters: the sandbox applies to Bash commands and their child processes. Claude's other built-in tools have their own permission model.

## macOS

**Native sandbox: strong**

Claude Code uses the macOS **Seatbelt** framework.

The sandbox can restrict:

- filesystem reads and writes;
- allowed network domains;
- subprocess behavior.

Run:

```text
/sandbox
```

Claude Code can run sandboxed commands automatically while still requiring approval when a command needs to escape the configured boundary.

Strict deployments can also disable the unsandboxed retry path.

## Linux

**Native sandbox: strong**

Claude uses **bubblewrap (`bwrap`)** for filesystem isolation and `socat` for the sandbox network proxy. An optional seccomp component can further constrain Unix socket behavior.

On distributions that restrict unprivileged user namespaces, additional host configuration may be required before bubblewrap can work.

## Windows native

**Native sandbox: not supported**

Anthropic explicitly documents native Windows as unsupported for Claude Code's sandbox.

Use WSL2 when you want the native Claude Code sandbox on a Windows client.

## WSL2

**Native sandbox: Linux implementation**

Claude uses the Linux bubblewrap path inside WSL2.

One Windows-specific concern is interop: WSL can launch Windows binaries through host integration. Claude documents additional socket/seccomp considerations if you need to prevent a sandboxed Linux process from escaping through Windows executable interop.

## Claude-specific credential isolation

Claude's current sandbox has unusually useful credential controls.

`sandbox.credentials.envVars` can remove or mask selected variables from sandboxed Bash commands. Mask mode can show the command a sentinel value while a proxy injects the real credential only to allowed hosts.

That is stronger than simply putting a real token in `--env-file`.

---

# 9. Native isolation: OpenAI Codex CLI

Codex separates approval policy from sandbox policy and has substantial platform-specific sandbox implementations.

## macOS

**Native sandbox: strong**

Codex uses macOS Seatbelt through `/usr/bin/sandbox-exec` and generates profiles that constrain filesystem and network behavior.

## Linux

**Native sandbox: strong**

Current Codex source uses **bubblewrap as the default Linux filesystem sandbox**.

The implementation can:

- expose `/` read-only;
- reopen configured writable roots;
- re-protect sensitive paths under writable roots;
- isolate user and PID namespaces;
- isolate the network namespace when network is restricted;
- apply `PR_SET_NO_NEW_PRIVS`;
- apply seccomp network filtering;
- route allowed traffic through a managed proxy.

Codex also retains a legacy **Landlock + mount protections** path for compatible configurations.

## Windows native

**Native sandbox: real, but platform-specific and evolving**

Codex contains a dedicated Windows sandbox implementation rather than relying only on approval prompts.

Current source includes:

- dedicated sandbox principals/users;
- ACL-based filesystem restrictions;
- explicit read/write roots;
- deny-read handling;
- Windows Filtering Platform network policy;
- online/offline sandbox identities;
- setup and diagnostic flows.

The implementation is substantial enough that Windows should not be described as "no sandbox," but its architecture is different from the Linux/macOS implementations.

## WSL2

**Native sandbox: strong Linux path**

Codex explicitly uses its normal Linux bubblewrap path on WSL2.

WSL1 does not provide the user-namespace behavior required for that path.

---

# 10. Native isolation: OpenCode

OpenCode is the clearest example of why **permissions are not containment**.

Its V2 permission system can:

- allow an operation;
- deny an operation;
- ask before an operation;
- separately gate external-directory access.

That is useful policy.

However, the current OpenCode documentation explicitly warns that the `shell` tool runs with the host user's **filesystem, process, and network authority**.

## macOS

**Native sandbox: permissions only**

There is no documented OpenCode-owned equivalent to Claude/Codex Seatbelt sandboxing.

Use an external boundary when you need containment.

## Linux

**Native sandbox: permissions only**

Allowed OpenCode shell commands are not automatically placed into an OpenCode-owned bubblewrap, Landlock, namespace, or seccomp sandbox.

This is the main use case behind [`opencode-containment`](https://github.com/christian-taillon/opencode-containment).

## Windows native

**Native sandbox: permissions only**

OpenCode's approval model does not create a dedicated Windows restricted runtime comparable to Codex's Windows sandbox.

## WSL2

**Native sandbox: permissions only inside the WSL environment**

WSL2 changes the surrounding environment, but an allowed OpenCode command can still reach what the WSL user can reach, including Windows-mounted paths when available.

For OpenCode, external container or microVM containment is especially useful.

---

# 11. Native isolation: Cursor

Cursor has a real sandbox layer in addition to its command-review/permission behavior.

Cursor's `permissions.json` and `sandbox.json` solve different problems:

- permissions decide which actions require review;
- sandbox policy decides what sandboxed processes can actually reach.

## macOS

**Native sandbox: strong**

Cursor uses **Seatbelt through `sandbox-exec`**.

A generated profile constrains filesystem, network, and subprocess behavior.

## Linux

**Native sandbox: strong**

Cursor's Linux sandbox uses native Linux controls including **Landlock and seccomp**. Cursor also reports a bubblewrap fallback when that path is active.

Useful diagnostic variables include:

```bash
echo "$CURSOR_SANDBOX"
echo "$CURSOR_SANDBOX_LANDLOCK_STATUS"
```

The second variable reports states such as `fully_enforced` or `bubblewrap`.

<<insert image here: in a Cursor sandboxed terminal run `printf 'sandbox=%s\nbackend=%s\n' "$CURSOR_SANDBOX" "$CURSOR_SANDBOX_LANDLOCK_STATUS"` and capture the result>>

## Windows native

Cursor's published engineering description says its Windows implementation runs the **Linux sandbox inside WSL2** rather than building an unrelated Windows-native sandbox stack.

That means Windows users should think of Cursor's sandbox boundary as a managed WSL2/Linux isolation path.

## WSL2

When Cursor's sandbox runs through WSL2, evaluate the reachable Windows mounts and host interop just as you would for other WSL-based agent setups.

---

# 12. Cross-harness native isolation summary

| Harness | macOS | Linux | Windows client | WSL2 |
|---|---|---|---|---|
| **Claude Code** | Seatbelt | bubblewrap + network proxy | Native sandbox unsupported | Linux bubblewrap path |
| **Codex CLI** | Seatbelt | bubblewrap + seccomp; legacy Landlock available | Dedicated Windows sandbox | Normal Linux bubblewrap path |
| **OpenCode** | Permissions only | Permissions only | Permissions only | Permissions only |
| **Cursor** | Seatbelt | Landlock/seccomp, bubblewrap fallback | Linux sandbox through WSL2 | Linux sandbox path |

This table is about **runtime isolation**, not model quality, coding quality, permissions UX, or product security overall.

---

# 13. Native sandbox vs. container vs. microVM

| Boundary | Useful against | Does not automatically prevent |
|---|---|---|
| Harness approvals | accidental or disallowed actions | an allowed command using broad OS authority |
| Harness native sandbox | filesystem/network/process access outside policy | damage inside writable areas; deliberately supplied credentials |
| Docker/Podman | broad host filesystem/process exposure | shared-kernel escape risk; damage to writable mounts |
| Docker Sandbox microVM | stronger whole-environment and kernel separation | damage to intentionally shared workspace; misuse of deliberately granted access |

No layer fixes an overly broad mount or overly powerful credential.

A strong practical design usually looks like:

```text
workspace      -> only the project
write access   -> only where code must change
agent config   -> only the harness state it needs
runtime env    -> only configuration it actually needs
credentials    -> scoped, proxied, or kept in a separate runner
network        -> only what the task requires
host           -> otherwise absent
```

---

# 14. Suggested starting points

## Lowest-friction stronger boundary

```bash
sbx run --clone AGENT
```

## Normal development with changes landing directly in the checkout

```bash
sbx run AGENT
```

## Existing Docker-based development environment

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  AGENT_IMAGE
```

## Local application needs secrets but agent does not

Keep the secret env file outside the workspace and inject it into a **separate test/runtime process**, not the agent.

## OpenCode power user

Use [`opencode-containment`](https://github.com/christian-taillon/opencode-containment) as a more opinionated reference implementation rather than rebuilding all of the state handling and guardrails in one increasingly complicated `docker run` command.

---

# References

## Docker

- Docker Sandboxes: <https://docs.docker.com/ai/sandboxes/>
- Docker Sandboxes usage and environment variables: <https://docs.docker.com/ai/sandboxes/usage/>
- Docker Sandboxes credentials: <https://docs.docker.com/ai/sandboxes/configuration/credentials/>
- `sbx secret`: <https://docs.docker.com/reference/cli/sbx/secret/>
- Experimental custom secrets: <https://docs.docker.com/reference/cli/sbx/secret/set-custom/>
- `docker run --env-file`: <https://docs.docker.com/reference/cli/docker/container/run/>
- Docker Compose secrets: <https://docs.docker.com/compose/how-tos/use-secrets/>

## Harnesses

- Claude Code sandboxing: <https://code.claude.com/docs/en/sandboxing>
- Codex security/sandboxing: <https://developers.openai.com/codex/security>
- Codex Linux sandbox source: <https://github.com/openai/codex/tree/main/codex-rs/linux-sandbox>
- Codex Windows sandbox source: <https://github.com/openai/codex/tree/main/codex-rs/windows-sandbox-rs>
- OpenCode V2 permissions: <https://opencode.ai/v2/docs/permissions>
- Cursor run modes: <https://cursor.com/docs/agent/security/run-modes>
- Cursor sandbox configuration: <https://cursor.com/docs/reference/sandbox>
- Cursor sandbox engineering overview: <https://cursor.com/blog/agent-sandboxing>

## Opinionated reference implementation

- OpenCode containment: <https://github.com/christian-taillon/opencode-containment>
