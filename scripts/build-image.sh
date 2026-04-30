#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-opencode-containment:latest}"
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

add_build_arg_if_set HTTP_PROXY
add_build_arg_if_set HTTPS_PROXY
add_build_arg_if_set ALL_PROXY
add_build_arg_if_set NO_PROXY
add_build_arg_if_set http_proxy
add_build_arg_if_set https_proxy
add_build_arg_if_set all_proxy
add_build_arg_if_set no_proxy
add_build_arg_if_set NODE_EXTRA_CA_CERTS

if [[ -n "${OPENCODE_BUILD_EXTRA_APK_PACKAGES:-}" && -z "${EXTRA_APK_PACKAGES:-}" ]]; then
    DOCKER_BUILD_ARGS+=(--build-arg "EXTRA_APK_PACKAGES=${OPENCODE_BUILD_EXTRA_APK_PACKAGES}")
fi

add_build_arg_if_set EXTRA_APK_PACKAGES

exec docker build --pull "${DOCKER_BUILD_ARGS[@]}" -t "$IMAGE_NAME" "$ROOT_DIR"
