#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT_DIR/bin/opencode-container"
IMAGE="${OPENCODE_TEST_IMAGE:-opencode-containment:latest}"
mkdir -p /tmp/opencode
TEST_DIR="$(mktemp -d /tmp/opencode/v2-runtime.XXXXXX)"
container_id=""
network_name=""
cleanup() {
    local status=$?
    [[ -z "$container_id" ]] || docker rm -f "$container_id" >/dev/null 2>&1 || true
    [[ -z "$network_name" ]] || docker network rm "$network_name" >/dev/null 2>&1 || true
    if [[ "$status" == 0 ]]; then
        rm -rf -- "$TEST_DIR"
    else
        printf 'Runtime test evidence retained at %s\n' "$TEST_DIR" >&2
    fi
}
trap cleanup EXIT
trap 'printf "Runtime test failed at line %s.\n" "$LINENO" >&2' ERR
export HOME="$TEST_DIR/home"
export OPENCODE_CONTAINER_HOME="$TEST_DIR/state"
export OPENCODE_CONFIG_DIR="$TEST_DIR/config"
export OPENCODE_SYNC_HOST_AUTH=0 OPENCODE_SYNC_CONFIG_CACHE=0 OPENCODE_SYNC_CONFIG_STATE=0
export OPENCODE_JEV_PLUGIN_DIR=""
unset SSH_AUTH_SOCK GITHUB_TOKEN GH_TOKEN TYPESAFE_API_KEY OPENCODE_CONFIG_CONTENT OPENCODE_OVERRIDES_FILE
mkdir -p "$HOME" "$OPENCODE_CONFIG_DIR" "$TEST_DIR/workspace"
cat > "$OPENCODE_CONFIG_DIR/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "update": "disable",
  "permissions": [{"action": "shell", "resource": "*", "effect": "ask"}],
  "agents": {"plan": {"permissions": [{"action": "edit", "resource": "*", "effect": "deny"}]}}
}
JSON
cd "$TEST_DIR/workspace"

launch() {
    "$LAUNCHER" --image "$IMAGE" "$@"
}
value() {
    awk -F ': ' -v label="$1" '$1 == label { count++; value = $2 } END { if (count != 1 || value == "") exit 1; print value }' "$2"
}
json_output() {
    awk 'substr($0, 1, 1) == "{" || substr($0, 1, 2) == "[{" { found=1 } found' "$1"
}
free_port() {
    python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

launch --version > "$TEST_DIR/version"
grep -Eq '^(opencode v)?2\.[0-9]+\.[0-9]+$' "$TEST_DIR/version"
launch api get /api/config --standalone > "$TEST_DIR/config-result"
json_output "$TEST_DIR/config-result" | jq -e '[.[] | select(.type == "document") | .info][0] | .permissions[0].action == "shell" and .agents.plan.permissions[0].effect == "deny"' >/dev/null
launch api post /api/session --standalone --data '{"title":"V2 persistence smoke"}' > "$TEST_DIR/created"
session_id="$(json_output "$TEST_DIR/created" | jq -er '.data.id')"
launch api get "/api/session/$session_id" --standalone > "$TEST_DIR/resumed"
json_output "$TEST_DIR/resumed" | jq -e '.data.title == "V2 persistence smoke"' >/dev/null
printf 'V2 CLI, native permissions, and session persistence passed.\n'

port="$(free_port)"
launch --web-server start --web-port "$port" > "$TEST_DIR/start"
container_id="$(value '  Container ID' "$TEST_DIR/start")"
network_name="$(value '  Network' "$TEST_DIR/start")"
credentials_file="$(value '  Basic Auth credentials' "$TEST_DIR/start")"
[[ "$(docker container inspect --format '{{range (index .NetworkSettings.Ports "'"$port"'/tcp")}}{{println .HostIp}}{{end}}' "$container_id")" == 127.0.0.1 ]]
[[ "$(stat -c '%a' "$credentials_file")" == 600 ]]
username=""
password=""
while IFS='=' read -r key val; do
    case "$key" in
        OPENCODE_SERVER_USERNAME) username="$val" ;;
        OPENCODE_SERVER_PASSWORD) password="$val" ;;
        *) exit 1 ;;
    esac
done < "$credentials_file"
[[ "$username" == opencode && "$password" =~ ^[0-9a-f]{64}$ ]]
auth_config="$TEST_DIR/curl-auth"
(umask 077; printf 'user = "%s:%s"\n' "$username" "$password" > "$auth_config")
url="http://127.0.0.1:$port/api/info"
[[ "$(curl --disable --silent --output /dev/null --write-out '%{http_code}' --noproxy 127.0.0.1 "$url")" == 401 ]]
[[ "$(curl --disable --silent --user opencode:wrong-password --output /dev/null --write-out '%{http_code}' --noproxy 127.0.0.1 "$url")" == 401 ]]
curl --disable --silent --show-error --fail --config "$auth_config" --noproxy 127.0.0.1 "$url" | jq -e '.version | startswith("2.")' >/dev/null
launch --web-server status --web-port "$port" > "$TEST_DIR/status"
[[ "$(value '  Service' "$TEST_DIR/status")" == running ]]
docker stop "$container_id" >/dev/null
launch --web-server status --web-port "$port" > "$TEST_DIR/status"
[[ "$(value '  Service' "$TEST_DIR/status")" == stopped ]]
launch --web-server stop --web-port "$port" > "$TEST_DIR/stop"
[[ -f "$credentials_file" ]]
if docker container inspect "$container_id" >/dev/null 2>&1 || docker network inspect "$network_name" >/dev/null 2>&1; then
    exit 1
fi
container_id=""
network_name=""
launch --web-server start --web-port "$port" > "$TEST_DIR/start"
container_id="$(value '  Container ID' "$TEST_DIR/start")"
network_name="$(value '  Network' "$TEST_DIR/start")"
[[ "$(value '  Basic Auth credentials' "$TEST_DIR/start")" == "$credentials_file" ]]
curl --disable --silent --show-error --fail --config "$auth_config" --noproxy 127.0.0.1 "$url" >/dev/null
launch --web-server stop --web-port "$port" > "$TEST_DIR/stop"
container_id=""
network_name=""
printf 'V2 web authentication, credential reuse, and lifecycle passed.\n'

port="$(free_port)"
launch --web-server start --web-port "$port" --network-accessible > "$TEST_DIR/start" 2> "$TEST_DIR/warning"
container_id="$(value '  Container ID' "$TEST_DIR/start")"
network_name="$(value '  Network' "$TEST_DIR/start")"
grep -Fq 'WARNING: --network-accessible' "$TEST_DIR/warning"
[[ "$(docker container inspect --format '{{range (index .NetworkSettings.Ports "'"$port"'/tcp")}}{{println .HostIp}}{{end}}' "$container_id")" == 0.0.0.0 ]]
launch --web-server stop --web-port "$port" > "$TEST_DIR/stop"
container_id=""
network_name=""
printf 'Explicit LAN publication passed.\n'
