#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-opencode-containment:latest}"
BUILD_TARGET="${OPENCODE_BUILD_TARGET:-container}"
DOCKER_BUILD_ARGS=()

add_build_arg_if_set() {
    local var="$1"
    if [[ -n "${!var:-}" ]]; then
        DOCKER_BUILD_ARGS+=(--build-arg "$var=${!var}")
    fi
}

LOCAL_HOOK="$ROOT_DIR/opencode-local.sh"
if [[ -f "$LOCAL_HOOK" ]]; then
    # shellcheck disable=SC1090
    source "$LOCAL_HOOK"
fi

if [[ "${OPENCODE_BUILD_NO_CACHE:-}" == "1" || "${OPENCODE_BUILD_NO_CACHE:-}" == "true" ]]; then
    DOCKER_BUILD_ARGS+=(--no-cache)
fi

add_build_arg_if_set HTTP_PROXY
add_build_arg_if_set HTTPS_PROXY
add_build_arg_if_set ALL_PROXY
add_build_arg_if_set NO_PROXY
add_build_arg_if_set http_proxy
add_build_arg_if_set https_proxy
add_build_arg_if_set all_proxy
add_build_arg_if_set no_proxy
add_build_arg_if_set NODE_EXTRA_CA_CERTS
case "$BUILD_TARGET" in
    container|sandbox) ;;
    *) echo "Error: OPENCODE_BUILD_TARGET must be container or sandbox." >&2; exit 1 ;;
esac

OPENCODE_VERSION="${OPENCODE_VERSION:-latest}"
if [[ "$OPENCODE_VERSION" == "latest" ]]; then
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl is required to resolve the latest OpenCode V2 release, or pin OPENCODE_VERSION=2.x.y." >&2
        exit 1
    fi
    if ! release_metadata="$(curl --fail --silent --show-error --location --connect-timeout 10 --max-time 60 https://opencode.ai/update/api/latest/cli/npm)"; then
        echo "Error: Could not resolve the latest OpenCode V2 release. Retry or pin OPENCODE_VERSION=2.x.y." >&2
        exit 1
    fi
    version_pattern='"version"[[:space:]]*:[[:space:]]*"([^"]*)"'
    if [[ "$release_metadata" =~ $version_pattern ]]; then
        OPENCODE_VERSION="${BASH_REMATCH[1]}"
    else
        echo "Error: OpenCode release metadata is missing a version. Retry or pin OPENCODE_VERSION=2.x.y." >&2
        exit 1
    fi
fi
if [[ ! "$OPENCODE_VERSION" =~ ^2\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: OPENCODE_VERSION must resolve to a stable V2 release (2.x.y); use latest or an explicit version." >&2
    exit 1
fi
echo "Building OpenCode V${OPENCODE_VERSION} (${BUILD_TARGET} image)."
add_build_arg_if_set OPENCODE_VERSION
add_build_arg_if_set RUST_TOOLCHAIN
add_build_arg_if_set UV_VERSION
add_build_arg_if_set UV_INSTALLER_SHA256
add_build_arg_if_set MARKSMAN_VERSION
add_build_arg_if_set MARKSMAN_SHA256_X86_64
add_build_arg_if_set MARKSMAN_SHA256_AARCH64

if [[ -n "${OPENCODE_BUILD_EXTRA_APK_PACKAGES:-}" && -z "${EXTRA_APK_PACKAGES:-}" ]]; then
    DOCKER_BUILD_ARGS+=(--build-arg "EXTRA_APK_PACKAGES=${OPENCODE_BUILD_EXTRA_APK_PACKAGES}")
fi

add_build_arg_if_set EXTRA_APK_PACKAGES

exec docker build --pull "${DOCKER_BUILD_ARGS[@]}" --target "$BUILD_TARGET" -t "$IMAGE_NAME" "$ROOT_DIR"
