#!/usr/bin/env bash
set -euo pipefail

image="${OPENCODE_TEST_SANDBOX_IMAGE:-localhost/opencode-containment-sandbox:latest}"
mkdir -p /tmp/opencode
config_dir="$(mktemp -d /tmp/opencode/v2-sandbox-config.XXXXXX)"
trap 'rm -f "$config_dir/opencode.json"; rmdir "$config_dir"' EXIT
printf '{"permissions":[{"action":"shell","resource":"*","effect":"ask"}],"agents":{"plan":{"permissions":[{"action":"edit","resource":"*","effect":"deny"}]}}}\n' > "$config_dir/opencode.json"
chmod 755 "$config_dir"
chmod 644 "$config_dir/opencode.json"
docker run --rm --network none --volume "$config_dir:/opt/test-config:ro" \
    --env OPENCODE_CONFIG_DIR=/opt/test-config --entrypoint /bin/sh "$image" -ec '
    test "$(id -un)" = agent
    test "$(id -u)" = 1000
    test "$HOME" = /home/agent
    test -w "$HOME"
    version="$(opencode --version)"
    case "$version" in "opencode v2."*|2.*) ;; *) exit 1 ;; esac
    sudo -n true
    test "$(HTTPS_PROXY=https://fixture.invalid sudo -n printenv HTTPS_PROXY)" = https://fixture.invalid
    printf "[]\n" > /tmp/test-credentials.json
    opencode auth import --standalone /tmp/test-credentials.json
    test "$(opencode auth export --standalone)" = "[]"
    opencode api get /api/config --standalone | jq -e '\''[.[] | select(.type == "document") | .info][0] | .agents.plan.permissions[0].effect == "deny"'\'' >/dev/null
    printf "V2 sandbox image contract and native credential import/export passed.\n"
'
