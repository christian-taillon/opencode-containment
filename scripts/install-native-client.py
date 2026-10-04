#!/usr/bin/env python3
"""Install a verified V2 binary, never replacing a user's opencode/opencode2."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import stat
import tarfile
import tempfile
import urllib.request


def artifact(pin, arch, libc, version=None, sha512=None):
    arches = {"x86_64": "x64-baseline", "aarch64": "arm64", "arm64": "arm64"}
    if arch not in arches or libc not in {"glibc", "musl"}:
        raise ValueError("Only Linux x86_64/arm64 glibc/musl clients are supported")
    package = "cli-linux-" + arches[arch] + ("-musl" if libc == "musl" else "")
    version = version or pin["version"]
    if not re.fullmatch(r"2\.\d+\.\d+", version):
        raise ValueError("Expected an explicit V2 release version")
    if version != pin["version"] and not sha512:
        raise ValueError("Version overrides require a matching explicit SHA-512 digest")
    checksum = sha512 or pin["sha512"][package]
    if not re.fullmatch(r"[0-9a-f]{128}", checksum):
        raise ValueError("Expected a lowercase SHA-512 digest")
    return package, version, checksum


def safe_parent(path):
    path = Path(os.path.abspath(path))
    for parent in reversed((path, *path.parents)):
        try:
            info = parent.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode):
            raise ValueError("Install path must not traverse symlinks")
        if not stat.S_ISDIR(info.st_mode):
            raise ValueError("Install ancestor must be a directory")
        trusted_sticky = info.st_uid == 0 and info.st_mode & stat.S_ISVTX
        if info.st_uid not in {0, os.getuid()} or (info.st_mode & 0o022 and not trusted_sticky):
            raise ValueError("Install ancestor is not trusted or is writable by peers")
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = path.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o022:
        raise ValueError("Install directory must be user-owned and not writable by peers")


def install(archive, target, package, version, checksum):
    if hashlib.sha512(archive.read_bytes()).hexdigest() != checksum:
        raise ValueError("Artifact SHA-512 verification failed")
    # Read only two exact regular members; never extract paths or follow tar links.
    with tarfile.open(archive, "r:gz") as tar:
        members = tar.getmembers()
        selected = {}
        for name in ("package/package.json", "package/bin/opencode"):
            matches = [member for member in members if member.name == name]
            if len(matches) != 1 or not matches[0].isfile():
                raise ValueError("Artifact must contain unique regular metadata and binary")
            selected[name] = matches[0]
        metadata = json.load(tar.extractfile(selected["package/package.json"]))
        if metadata.get("name") != "@opencode/" + package or metadata.get("version") != version:
            raise ValueError("Artifact package/version verification failed")
        safe_parent(target.parent)
        if target.is_symlink() or (target.exists() and not target.is_file()):
            raise ValueError("Install target must be a regular file, not a symlink")
        fd, temporary = tempfile.mkstemp(prefix=".opencode2-", dir=target.parent)
        try:
            with os.fdopen(fd, "wb") as stream, tar.extractfile(selected["package/bin/opencode"]) as binary:
                while chunk := binary.read(1024 * 1024):
                    stream.write(chunk)
                stream.flush()
                os.fchmod(stream.fileno(), 0o755)
                os.fsync(stream.fileno())
            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--libc", choices=("glibc", "musl"), default="musl" if Path("/etc/alpine-release").exists() else "glibc")
    p.add_argument("--version", default=os.environ.get("OPENCODE2_VERSION") or None)
    p.add_argument("--sha512", help="Required with a non-default version")
    p.add_argument("--image-install", action="store_true", help="Image-build-only root install to /usr/local/bin/opencode2")
    p.add_argument("--check-pin", action="store_true", help="Validate platform/version/digest selection without installing")
    args = p.parse_args()
    if platform.system() != "Linux":
        p.error("Managed native client installation supports Linux only")
    pin = json.loads((Path(__file__).resolve().parents[1] / "config/opencode2-pin.json").read_text())
    arch = platform.machine()
    checksum = args.sha512 or os.environ.get("OPENCODE2_TARBALL_SHA512_" + ("X86_64" if arch == "x86_64" else "AARCH64")) or (os.environ.get("OPENCODE2_TARBALL_SHA512") if arch == "x86_64" else None) or None
    package, version, checksum = artifact(pin, arch, args.libc, args.version, checksum)
    if args.check_pin:
        print("@opencode/" + package + " " + version + " SHA-512 " + checksum)
        return
    root = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
    if args.image_install and (os.getuid() != 0 or not Path("/etc/alpine-release").exists()):
        p.error("--image-install is restricted to root in the Alpine image build")
    target = Path("/usr/local/bin/opencode2") if args.image_install else root / "opencode-containment/clients" / version / "opencode2"
    safe_parent(target.parent)
    url = f"https://registry.npmjs.org/@opencode/{package}/-/{package}-{version}.tgz"
    with tempfile.TemporaryDirectory(prefix=".download-", dir=target.parent) as temp:
        archive = Path(temp) / "client.tgz"
        with urllib.request.urlopen(url, timeout=60) as response, archive.open("wb") as stream:
            while chunk := response.read(1024 * 1024):
                stream.write(chunk)
        install(archive, target, package, version, checksum)
    print(target)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, tarfile.TarError) as error:
        raise SystemExit("Native client installation failed: " + str(error))
