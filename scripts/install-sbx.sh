#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" == --help ]]; then
    echo "Usage: $0 [path/to/DockerSandboxes-linux-amd64.tar.gz]"
    echo 'Install pinned sbx v0.46.0 for your user; download if no archive is supplied.'
    echo 'Logs: /tmp/opencode/sbx-install.*/install.log. No login or daemon startup.'
    exit 0
fi

umask 077
mkdir -p /tmp/opencode
work_dir="$(mktemp -d /tmp/opencode/sbx-install.XXXXXX)"
log_file="$work_dir/install.log"
exec > >(tee "$log_file") 2>&1
trap 'status=$?; echo "Finished: $(date -Is), exit=$status; log: $log_file"' EXIT
trap 'echo "ERROR: line $LINENO failed (exit $?)." >&2' ERR

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

echo "Started: $(date -Is); log: $log_file"
echo 'Scope: user-only installation and offline validation; no Docker Engine, login, or daemon.'
echo 'Fedora is outside Docker’s documented supported Linux distribution.'
[[ $# -le 1 ]] || fail 'Expected at most one archive path; see --help.'
[[ $EUID -ne 0 ]] || fail 'Run as your normal user, not with sudo.'
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || fail 'This pin supports Linux x86_64 only.'
for tool in tar sha256sum install readlink podman docker rpm mkfs.ext4; do
    command -v "$tool" >/dev/null || fail "Missing prerequisite: $tool (install separately)."
done
[[ -r /dev/kvm && -w /dev/kvm ]] || fail 'Your user needs read/write access to /dev/kvm.'
id -nG | tr ' ' '\n' | grep -qx kvm || fail 'Your user must belong to the kvm group; log in again after any group change.'
# The upstream installer can write a system AppArmor profile on other hosts.
[[ ! -d /sys/kernel/security/apparmor ]] || fail 'This host has AppArmor; review the upstream installer before installing.'

prefix="$HOME/.local/opt/docker-sbx-0.46.0"
[[ ! -e "$prefix" && ! -L "$prefix" ]] || fail "Refusing to overwrite existing installation: $prefix"

snapshot() {
    local tool path
    for tool in podman docker; do
        path="$(command -v "$tool")"
        printf '%s path: %s -> %s\n' "$tool" "$path" "$(readlink -f "$path")"
        sha256sum "$path"
    done
    podman --version
    rpm -q podman podman-docker
}

echo 'Recording Podman/docker executable and package identities before installation:'
snapshot > "$work_dir/before.txt"
cat "$work_dir/before.txt"

archive="${1:-$work_dir/DockerSandboxes-linux-amd64.tar.gz}"
if [[ $# -eq 0 ]]; then
    command -v curl >/dev/null || fail 'curl is required to download the bundle.'
    echo 'Downloading official sbx v0.46.0 Linux amd64 bundle...'
    curl --fail --location --proto '=https' --proto-redir '=https' --retry 2 \
        --connect-timeout 20 --max-time 600 \
        --output "$archive" \
        https://github.com/docker/sbx-releases/releases/download/v0.46.0/DockerSandboxes-linux-amd64.tar.gz
fi
[[ -f "$archive" ]] || fail "Archive not found: $archive"
# GitHub release asset SHA-256 for v0.46.0, not an unpinned latest release.
expected=edd86e2f21559e190723fd884c3a1dced161a555afdff85c5921ed45e7d6d56e
# Copy before verification so extraction uses the same private, verified bytes.
cp -- "$archive" "$work_dir/verified.tar.gz"
echo "$expected  $work_dir/verified.tar.gz" | sha256sum -c -
mkdir "$work_dir/source"
tar --extract --gzip --file "$work_dir/verified.tar.gz" \
    --directory "$work_dir/source" --no-same-owner --no-same-permissions
source_dir="$work_dir/source/docker-sbx"
[[ -f "$source_dir/install.sh" ]] || fail 'Verified archive has an unexpected layout.'

echo "Installing to $prefix (no sudo, PATH changes, or system services)..."
PREFIX="$prefix" bash "$source_dir/install.sh"

echo 'Checking installed bundle integrity...'
files=(
    'sbx:bin/sbx'
    'containerd-shim-nerdbox-v1:libexec/containerd-shim-nerdbox-v1'
    'containerd-shim-nerdbox-gpu-v1:libexec/containerd-shim-nerdbox-gpu-v1'
    'mkfs.erofs:libexec/mkfs.erofs'
    'libsailor.so:libexec/lib/libsailor.so'
    'nerdbox-kernel-x86_64:libexec/nerdbox-kernel-x86_64'
    'nerdbox-rootfs-x86_64.erofs:libexec/nerdbox-rootfs-x86_64.erofs'
)
for file in "${files[@]}"; do
    cmp -- "$source_dir/${file%%:*}" "$prefix/${file#*:}"
    echo "OK: ${file#*:}"
done
version="$("$prefix/bin/sbx" version)"
echo "$version"
[[ "$version" == 'sbx version: v0.46.0 '* ]] || fail 'Installed CLI version does not match the pin.'
"$prefix/bin/sbx" --help

echo 'Checking Podman/docker executable and package identities after installation:'
snapshot > "$work_dir/after.txt"
cat "$work_dir/after.txt"
cmp -- "$work_dir/before.txt" "$work_dir/after.txt" || fail 'Podman/docker identities changed; inspect before.txt and after.txt.'
echo 'PASS: bundle integrity and CLI checks; Podman/docker paths, bytes, version, and package versions unchanged.'
echo 'NOT TESTED: daemon startup, authentication, VM operation, networking, or native attach compatibility.'
printf 'Use explicitly: %q version\n' "$prefix/bin/sbx"
echo 'Archive and diagnostic files are retained alongside the log.'
