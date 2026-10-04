#!/usr/bin/env python3
"""Standalone, in-sandbox V2 alpha. Not a native host attach backend."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("native_install", ROOT / "scripts/install-native-client.py")
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
DEFAULTS = {
    "cpus": 2,
    "memory": "4g",
    "template": "docker/sandbox-templates@sha256:1560168ac5fb9ce23d413c878349334c5845c07e264cd675d7867f0c78ad1761",
    "network_allow": ["models.dev:443", "opencode.ai:443", "api.opencode.ai:443", "api.anthropic.com:443",
                      "console.anthropic.com:443", "api.openai.com:443", "auth.openai.com:443",
                      "generativelanguage.googleapis.com:443", "openrouter.ai:443"],
    "environment": {},
    "sbx": None,
}
PROJECT_KEYS = {"cpus", "memory"}
GUEST = "/home/agent/.local/share/opencode-containment/alpha"
BOOTSTRAP = """import json,os,pathlib,sys
payload=json.load(sys.stdin)
root=pathlib.Path('/home/agent/.local/share/opencode-containment/alpha')
for name in ['config/opencode','data','cache','state','home']:
    path=root/name
    path.mkdir(parents=True,exist_ok=True,mode=0o700)
    path.chmod(0o700)
config=payload['opencode']
config['update']='disable'
(root/'config/opencode/opencode.json').write_text(json.dumps(config))
(root/'environment.json').write_text(json.dumps(payload['environment']))
for path in [root/'config/opencode/opencode.json',root/'environment.json']:
    path.chmod(0o600)
"""
EXECUTE = """import json,os,sys
root='/home/agent/.local/share/opencode-containment/alpha'
env={'HOME':root+'/home','PATH':'/usr/local/bin:/usr/bin:/bin',
     'TERM':os.environ.get('TERM','xterm-256color'),
     'XDG_CONFIG_HOME':root+'/config','XDG_DATA_HOME':root+'/data',
     'XDG_CACHE_HOME':root+'/cache','XDG_STATE_HOME':root+'/state'}
for name in ['HTTP_PROXY','HTTPS_PROXY','http_proxy','https_proxy','NO_PROXY','no_proxy',
             'NODE_EXTRA_CA_CERTS','SSL_CERT_FILE','REQUESTS_CA_BUNDLE']:
    if name in os.environ: env[name]=os.environ[name]
env.update(json.load(open(root+'/environment.json')))
os.execve(root+'/opencode2',[root+'/opencode2',*sys.argv[1:]],env)
"""


def read_json(path, default=None):
    try:
        info = path.lstat()
    except FileNotFoundError:
        return default
    if not stat.S_ISREG(info.st_mode) or info.st_size > 1024 * 1024:
        raise ValueError("Expected a regular JSON file <=1 MiB: " + str(path))
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError("Expected a JSON object: " + str(path))
    return value


def validate(values, project=False):
    allowed = PROJECT_KEYS if project else set(DEFAULTS)
    if not isinstance(values, dict) or set(values) - allowed:
        raise ValueError("Unknown sandbox setting" + ("; project overrides accept only cpus and memory" if project else ""))
    if "cpus" in values and (type(values["cpus"]) is not int or not 1 <= values["cpus"] <= 64):
        raise ValueError("cpus must be an integer from 1 to 64")
    if "memory" in values and (not isinstance(values["memory"], str) or not re.fullmatch(r"[1-9][0-9]*[mg]", values["memory"])):
        raise ValueError("memory must be a positive limit such as 4g or 1024m")
    if "memory" in values and memory_bytes(values["memory"]) < 512 * 1024**2:
        raise ValueError("memory must be at least 512m")
    for key in ("template", "sbx"):
        if key in values and values[key] is not None and (not isinstance(values[key], str) or not values[key] or any(c.isspace() or c == "\0" for c in values[key])):
            raise ValueError(key + " must be a nonempty single-line string")
    if values.get("template", "default") is None:
        raise ValueError("template cannot be null")
    if "network_allow" in values:
        rules = values["network_allow"]
        if not isinstance(rules, list) or any(not isinstance(rule, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*:[0-9]{1,5}", rule) or not 1 <= int(rule.rsplit(":", 1)[1]) <= 65535 for rule in rules):
            raise ValueError("network_allow accepts exact hostname:port entries, not wildcards")
    environment = values.get("environment", {})
    if not isinstance(environment, dict):
        raise ValueError("environment must contain literal string values")
    for key, value in environment.items():
        if (not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key) or
                key in {"HOME", "PATH", "PWD", "SHELL", "ENV", "BASH_ENV", "SSH_AUTH_SOCK", "CDPATH"} or
                key.startswith(("OPENCODE_", "XDG_", "LD_", "DYLD_", "PYTHON", "NODE_", "BUN_", "DOCKER_", "SBX_", "MCP_"))):
            raise ValueError("Reserved environment name: " + key)
        if not isinstance(value, str) or any(c in value for c in "\0\r\n"):
            raise ValueError("environment values must be single-line strings")
    return values


def memory_bytes(value):
    return int(value[:-1]) * 1024 ** (2 if value[-1] == "m" else 3)


def settings(global_path, workspace, args):
    global_config = read_json(global_path, {})
    if set(global_config) - {"sandbox"}:
        raise ValueError("Containment config accepts a sandbox object only")
    config = {**DEFAULTS, **validate(global_config.get("sandbox", {}))}
    cli = {key: getattr(args, key) for key in ("cpus", "memory", "sbx") if getattr(args, key) is not None}
    validate(cli)
    sources = ["built-in defaults"]
    if global_path.exists():
        sources.append(str(global_path))
    project_path = workspace / ".opencode-containment.json"
    if not args.no_project_config:
        project = read_json(project_path, {})
        if set(project) - {"sandbox"}:
            raise ValueError("Project config accepts a sandbox object only")
        overrides = validate(project.get("sandbox", {}), project=True)
        ceiling_cpus = cli.get("cpus", config["cpus"])
        ceiling_memory = cli.get("memory", config["memory"])
        if (("cpus" in overrides and overrides["cpus"] > ceiling_cpus) or
                ("memory" in overrides and memory_bytes(overrides["memory"]) > memory_bytes(ceiling_memory))):
            raise ValueError("Project resource limits cannot exceed trusted global defaults; approve increases globally or with CLI flags")
        config.update(overrides)
        if project_path.exists():
            sources.append(str(project_path))
    config.update(cli)
    if args.allow_network:
        config["network_allow"] = [*config["network_allow"], *args.allow_network]
    config["environment"] = dict(config["environment"])
    for argument in args.env:
        key, separator, value = argument.partition("=")
        if not separator:
            if key not in os.environ:
                raise ValueError("Explicitly requested environment variable is unset: " + key)
            value = os.environ[key]
        config["environment"][key] = value
    validate(config)
    config["network_allow"] = sorted(set(config["network_allow"]))
    return config, sources


def workspace_path(value):
    workspace = Path(value).resolve(strict=True)
    start = Path.cwd().resolve()
    forbidden = {Path("/"), Path("/tmp"), Path("/tmp/opencode"), Path.home().resolve()}
    if not workspace.is_dir() or workspace in forbidden or not workspace.is_relative_to(start):
        raise ValueError("Workspace must be the current directory or its descendant, not / or HOME")
    if any(workspace.is_relative_to(Path(root)) for root in ("/etc", "/proc", "/sys", "/dev", "/run")):
        raise ValueError("System directories cannot be workspaces")
    if any(part in {".ssh", ".gnupg", ".aws", ".config", ".local"} for part in workspace.parts):
        raise ValueError("Sensitive/support directories cannot be workspaces")
    return workspace


def atomic_json(path, value):
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".record-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def visible_config(config, sources, opencode_path, workspace):
    return {"sandbox": {**config, "environment": sorted(config["environment"])},
            "sources": sources + ["explicit CLI flags"],
            "global_opencode": str(opencode_path), "workspace": str(workspace)}


class Runtime:
    def __init__(self, executable):
        self.executable = str(Path(executable).resolve(strict=True))
        self.environment = {key: value for key, value in os.environ.items()
                            if key in {"HOME", "PATH", "LANG", "TERM", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"}}

    def call(self, *args, data=None, timeout=120):
        proc = subprocess.run([self.executable, *args], env=self.environment, input=data,
                              capture_output=True, text=True, timeout=timeout)
        if proc.returncode:
            raise RuntimeError("sbx " + args[0] + " failed: " + proc.stderr.strip())
        return proc.stdout

    def json(self, *args):
        return json.loads(self.call(*args))

    def find(self, name):
        matches = [item for item in self.json("ls", "--json")["sandboxes"] if item["name"] == name]
        if len(matches) > 1:
            raise ValueError("Ambiguous sandbox identity")
        return matches[0] if matches else None

    def owned(self, record):
        item = self.find(record["name"])
        if (not item or item.get("id") != record.get("id") or
                item.get("workspaces") != [record["workspace"]]):
            raise ValueError("Sandbox ownership changed; refusing execution/cleanup")
        return item


def executable(config):
    selected = config["sbx"] or os.environ.get("OPENCODE_SBX_BIN") or shutil.which("sbx")
    if not selected:
        for path in (Path.home() / ".docker/sbx/bin/sbx", Path.home() / ".local/opt/docker-sbx-0.46.0/bin/sbx"):
            if path.is_file():
                selected = str(path)
                break
    if not selected:
        raise ValueError("Install sbx and sign in with sbx login first")
    return shutil.which(selected) or selected


def preflight(runtime, start, check_sharing=True):
    if "sbx version: v0.46.0 " not in runtime.call("version"):
        raise ValueError("Standalone alpha currently requires tested sbx v0.46.0")
    status = runtime.json("daemon", "status", "--json")
    if status.get("status") != "running" and start:
        runtime.call("daemon", "start", "--detach", "--policy", "deny-all")
    if check_sharing:
        report = runtime.json("diagnose", "--json")
        bad = [check for check in report["checks"] if check["status"] != "pass"]
        if bad:
            raise ValueError("Sandbox prerequisites: " + "; ".join(check["name"] + ": " + check["message"] for check in bad) + ". Run sbx diagnose / sbx login.")
        runtime_settings = runtime.json("settings", "list", "--json")
        values = {item["key"]: item["value"] for item in runtime_settings}
        if values.get("ssh.agentForwardingEnabled") and values.get("ssh.agentSocketPath"):
            raise ValueError("Fixed host SSH-agent forwarding is configured; disable/restart it explicitly before using this alpha")
        if values.get("clipboard.imagePaste"):
            raise ValueError("Host clipboard sharing is enabled; disable it explicitly before using this alpha")
    return {"executable": runtime.executable,
            "sha256": hashlib.sha256(Path(runtime.executable).read_bytes()).hexdigest(),
            "socket": runtime.json("daemon", "status", "--json")["socket"]}


def client(state):
    pin = read_json(ROOT / "config/opencode2-pin.json")
    target = state / "clients" / pin["version"] / "opencode2"
    digest_path = target.with_suffix(".json")
    native.safe_parent(target.parent)
    with (target.parent / "install.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not target.exists():
            package, version, checksum = native.artifact(pin, platform.machine(), "glibc")
            print("Installing verified OpenCode V" + version + " (once)...", file=sys.stderr, flush=True)
            with tempfile.TemporaryDirectory(dir=target.parent) as directory:
                archive = Path(directory) / "client.tgz"
                url = f"https://registry.npmjs.org/@opencode/{package}/-/{package}-{version}.tgz"
                with urllib.request.urlopen(url, timeout=60) as response, archive.open("wb") as stream:
                    shutil.copyfileobj(response, stream)
                native.install(archive, target, package, version, checksum)
            atomic_json(digest_path, {"sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
        if target.is_symlink() or not target.is_file():
            raise ValueError("Cached V2 client must be a regular file")
        if target.stat().st_uid != os.getuid() or target.stat().st_mode & 0o022:
            raise ValueError("Cached V2 client must be user-owned and not writable by peers")
        digest = read_json(digest_path)
        if not digest or digest.get("sha256") != hashlib.sha256(target.read_bytes()).hexdigest():
            raise ValueError("Cached V2 binary integrity failed; remove the cached opencode2 and opencode2.json, then rerun setup")
    return target


def run_client(runtime, record, arguments, keep_running):
    runtime.owned(record)
    command = [runtime.executable, "exec", "--workdir", record["workspace"]]
    if sys.stdin.isatty() and sys.stdout.isatty():
        command.append("-it")
    command += [record["name"], "python3", "-c", EXECUTE, *arguments]
    previous = {}
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    for number in (signal.SIGINT, signal.SIGTERM):
        previous[number] = signal.signal(number, interrupted)
    proc = None
    interrupted_run = False
    try:
        proc = subprocess.Popen(command, env=runtime.environment)
        result = proc.wait()
        return result
    except KeyboardInterrupt:
        interrupted_run = True
        return 130
    finally:
        for number in previous:
            signal.signal(number, signal.SIG_IGN)
        try:
            try:
                if proc and proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=10)
            finally:
                if not keep_running or interrupted_run or not proc or proc.returncode:
                    runtime.owned(record)
                    runtime.call("stop", record["name"])
        finally:
            for number, handler in previous.items():
                signal.signal(number, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", nargs="?", choices=("run", "setup", "doctor", "config", "status", "stop"), default="run")
    parser.add_argument("--workspace", default=os.getcwd())
    parser.add_argument("--config", type=Path, help="Trusted global containment config (default: XDG config/opencode-containment/config.json)")
    parser.add_argument("--state-dir", type=Path, help="Private alpha state/cache directory")
    parser.add_argument("--no-project-config", action="store_true")
    parser.add_argument("--sbx")
    parser.add_argument("--cpus", type=int)
    parser.add_argument("--memory")
    parser.add_argument("--allow-network", action="append", default=[], metavar="HOST:PORT")
    parser.add_argument("--env", action="append", default=[], metavar="NAME[=VALUE]")
    parser.add_argument("--keep-running", action="store_true", help="Explicitly retain a successful sandbox; sessions persist either way")
    raw = sys.argv[1:]
    split = raw.index("--") if "--" in raw else len(raw)
    args = parser.parse_args(raw[:split])
    forwarded = raw[split + 1:]
    if forwarded and args.action != "run":
        parser.error("OpenCode arguments after -- are accepted only for run")
    if args.action in {"stop", "status", "setup"}:
        args.no_project_config = True
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise ValueError("Standalone alpha is currently validated for Linux x86_64 only")
    if os.getuid() == 0:
        raise ValueError("Run as a normal user, not root")
    workspace = Path(args.workspace).resolve(strict=True) if args.action == "setup" else workspace_path(args.workspace)
    global_path = (args.config or Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "opencode-containment/config.json").expanduser().absolute()
    config, sources = settings(global_path, workspace, args)
    opencode_path = global_path.parent / "opencode.json"
    if args.action == "config":
        print(json.dumps(visible_config(config, sources, opencode_path, workspace), indent=2))
        return 0
    runtime = Runtime(executable(config))
    binding = preflight(runtime, args.action in {"setup", "run"}, args.action not in {"stop", "status"})
    if args.action == "doctor":
        print(json.dumps(visible_config(config, sources, opencode_path, workspace), indent=2))
        print("Standalone alpha runtime healthy; matching V2 is provisioned on setup/run.")
        return 0
    state = (args.state_dir or Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "opencode-containment/sandbox-alpha").expanduser().absolute()
    if args.action != "setup" and (state.resolve().is_relative_to(workspace) or workspace.is_relative_to(state.resolve())):
        raise ValueError("Private alpha state must be outside the shared workspace")
    native.safe_parent(state)
    if state.stat().st_mode & 0o077:
        raise ValueError("Alpha state directory must have mode 0700")
    if args.action == "setup":
        client(state)
        print("Standalone V2 alpha ready. Run opencode-sandbox-alpha from a project; model authorization happens in OpenCode.")
        return 0
    workspace_state = state / "workspaces" / hashlib.sha256(str(workspace).encode()).hexdigest()[:20]
    native.safe_parent(workspace_state)
    with (workspace_state / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        record_path = workspace_state / "instance.json"
        record = read_json(record_path)
        name = "opencode-alpha-" + workspace_state.name
        if record:
            if record.get("binding") != binding or record.get("workspace") != str(workspace):
                raise ValueError("Original runtime/workspace binding changed; restore it before recovery")
            if not record.get("id"):
                raise ValueError("Incomplete creation record; inspect the named sandbox and recover manually before retrying")
            runtime.owned(record)
        elif runtime.find(name):
            raise ValueError("Unrecorded sandbox name collision; refusing to adopt it")
        if args.action in {"status", "stop"}:
            if not record:
                print("No recorded alpha sandbox for this workspace.")
            elif args.action == "stop":
                runtime.call("stop", name)
            else:
                print(json.dumps(runtime.owned(record), indent=2))
            return 0
        creation = {key: config[key] for key in ("cpus", "memory", "template")}
        if record and record.get("creation") != creation:
            raise ValueError("Creation settings changed; existing sandbox/state preserved. Restore settings or explicitly remove the old sandbox and archive its instance.json before reprovisioning.")
        binary = client(state)
        opencode_config = read_json(opencode_path, {})
        if not record:
            record = {"name": name, "workspace": str(workspace), "binding": binding, "creation": creation}
            atomic_json(record_path, record)
            create = ("create", "--name", name, "--cpus", str(config["cpus"]), "--memory", config["memory"],
                      "--template", config["template"], "--skills", "off", "shell", str(workspace))
            try:
                runtime.call(*create, timeout=600)
            except RuntimeError as error:
                if ("global network policy has not been initialized" not in str(error) or
                        runtime.json("ls", "--json")["sandboxes"]):
                    raise
                runtime.call("policy", "init", "deny-all")
                runtime.call(*create, timeout=600)
            item = runtime.find(name)
            if not item or item["workspaces"] != [str(workspace)]:
                raise ValueError("Creation identity ambiguous; pending record preserved for manual recovery")
            record["id"] = item["id"]
            atomic_json(record_path, record)
        try:
            runtime.owned(record)
            runtime.call("stop", name)
            runtime.call("exec", "-i", name, "python3", "-c", BOOTSTRAP,
                         data=json.dumps({"opencode": opencode_config, "environment": config["environment"]}))
            digest = hashlib.sha256(binary.read_bytes()).hexdigest()
            guest_digest = runtime.call("exec", name, "python3", "-c",
                                        "import hashlib,pathlib; p=pathlib.Path(" + repr(GUEST + "/opencode2") + "); print(hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() and not p.is_symlink() else '')").strip()
            if guest_digest != digest:
                runtime.owned(record)
                runtime.call("cp", str(binary), name + ":" + GUEST + "/opencode2")
            runtime.call("exec", name, "chmod", "700", GUEST + "/opencode2")
            observed = runtime.call("exec", name, GUEST + "/opencode2", "--version").strip()
            expected = "opencode v" + read_json(ROOT / "config/opencode2-pin.json")["version"]
            if observed != expected:
                raise ValueError("Guest V2 version mismatch")
            rules = runtime.json("policy", "ls", name, "--json")["rules"]
            active = {resource for rule in rules
                      if rule.get("scope") == "sandbox:" + name and rule.get("editable") and rule.get("decision") == "allow"
                      and rule.get("resource_type") == "network" and rule.get("status") == "active"
                      for resource in rule.get("resources", [])}
            previous_network = record.get("network_allow", [])
            record["network_allow"] = sorted(set(previous_network) | set(config["network_allow"]))
            atomic_json(record_path, record)
            for resource in previous_network:
                if resource not in config["network_allow"] and resource in active:
                    runtime.owned(record)
                    runtime.call("policy", "rm", "network", "--sandbox", name, "--resource", resource, "--force")
            for resource in config["network_allow"]:
                if resource not in active:
                    runtime.owned(record)
                    runtime.call("policy", "allow", "network", "--sandbox", name, resource)
            record["network_allow"] = config["network_allow"]
            atomic_json(record_path, record)
        except BaseException:
            runtime.owned(record)
            runtime.call("stop", name)
            raise
        arguments = forwarded
        if not arguments or arguments[0].startswith("-"):
            arguments = ["--standalone", str(workspace), *arguments]
        elif arguments[0] in {"run", "mini", "api"}:
            arguments = [arguments[0], "--standalone", *arguments[1:]]
        print("Standalone V2 alpha: " + name + " (microVM semantics, not native attach hardening)", file=sys.stderr, flush=True)
        return run_client(runtime, record, arguments, args.keep_running)


if __name__ == "__main__":
    os.umask(0o077)
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit("Standalone sandbox alpha: " + str(error))
