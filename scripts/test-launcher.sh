#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$SCRIPT_DIR/bin/opencode-container"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
    echo "Test failed: $*" >&2
    exit 1
}

assert_line() {
    local expected="$1" file="$2" line

    while IFS= read -r line; do
        [[ "$line" == "$expected" ]] && return 0
    done < "$file"
    fail "missing line: $expected"
}

assert_no_line() {
    local unexpected="$1" file="$2" line

    while IFS= read -r line; do
        [[ "$line" == "$unexpected" ]] && fail "unexpected line: $unexpected"
    done < "$file"
    return 0
}

assert_arg_pair() {
    local flag="$1" value="$2" index

    for ((index = 0; index + 1 < ${#docker_args[@]}; index++)); do
        if [[ "${docker_args[index]}" == "$flag" && "${docker_args[index + 1]}" == "$value" ]]; then
            return 0
        fi
    done
    fail "missing Docker argument pair: $flag $value"
}

assert_command_tail() {
    local expected=("$@") index start

    start=$((${#docker_args[@]} - ${#expected[@]}))
    ((start >= 0)) || fail "Docker command is too short"
    for ((index = 0; index < ${#expected[@]}; index++)); do
        [[ "${docker_args[start + index]}" == "${expected[index]}" ]] || fail "unexpected Docker command"
    done
}

assert_no_server_env() {
    local index

    for ((index = 0; index + 1 < ${#docker_args[@]}; index++)); do
        if [[ "${docker_args[index]}" == "--env" && "${docker_args[index + 1]}" == OPENCODE_SERVER_USERNAME=* ]]; then
            fail "Docker metadata includes OPENCODE_SERVER_USERNAME"
        fi
        if [[ "${docker_args[index]}" == "--env" && "${docker_args[index + 1]}" == OPENCODE_SERVER_PASSWORD=* ]]; then
            fail "Docker metadata includes OPENCODE_SERVER_PASSWORD"
        fi
    done
}

assert_event() {
    assert_line "$1" "$DOCKER_EVENTS"
}

assert_no_event() {
    assert_no_line "$1" "$DOCKER_EVENTS"
}

assert_event_pattern() {
    local expected_pattern="$1" line

    while IFS= read -r line; do
        [[ "$line" == $expected_pattern ]] && return 0
    done < "$DOCKER_EVENTS"
    fail "missing event matching: $expected_pattern"
}

FAKE_BIN="$TEST_DIR/bin"
WORKSPACE="$TEST_DIR/workspace"
TEST_HOME="$TEST_DIR/home"
CONTAINER_HOME="$TEST_DIR/container-home"
DOCKER_LOG="$TEST_DIR/docker-args"
DOCKER_EVENTS="$TEST_DIR/docker-events"
DOCKER_CREATED_CONTAINER_FILE="$TEST_DIR/docker-created-container"
DOCKER_NETWORK_STATE_FILE="$TEST_DIR/docker-network-state"
CURL_EVENTS="$TEST_DIR/curl-events"
DOCKER_NETWORK_ID="ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
DOCKER_REPLACEMENT_NETWORK_ID="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
OUTPUT="$TEST_DIR/output"
INSTALLED_BIN="$TEST_DIR/installed-bin"
LINKED_LAUNCHER="$INSTALLED_BIN/opencode-container"
DOCKER_RUN_ID="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
mkdir -p "$FAKE_BIN" "$WORKSPACE" "$TEST_HOME" "$INSTALLED_BIN"
ln -s "$LAUNCHER" "$LINKED_LAUNCHER"

cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$DOCKER_EVENTS"
case "${1:-}" in
    --version)
        printf 'Docker version 28.0.0, build test\n'
        ;;
    version)
        [[ "${2:-}" == "--format" ]] || exit 1
        printf '%s\n' "${DOCKER_SERVER_VERSION:-28.0.0}"
        ;;
    container)
        if [[ "${2:-}" != "inspect" ]]; then
            exit 1
        fi
        if [[ "${DOCKER_CONTAINER_INSPECT_FAIL:-0}" == "1" ]]; then
            printf 'permission denied\n' >&2
            exit 1
        fi
        if [[ "${DOCKER_CONTAINER_INSPECT_FORMAT_INVALID:-0}" == "1" ]]; then
            printf 'invalid inspection output\n'
            exit 0
        fi
        requested_name=""
        for argument in "$@"; do
            requested_name="$argument"
        done
        if [[ -n "${DOCKER_CREATED_CONTAINER_FILE:-}" && -f "$DOCKER_CREATED_CONTAINER_FILE" ]]; then
            if IFS=' ' read -r created_name created_id created_ownership created_token created_running created_binding < "$DOCKER_CREATED_CONTAINER_FILE" \
                && [[ "$requested_name" == "$created_name" || "$requested_name" == "$created_id" ]]; then
                if [[ "${3:-}" == "--format" ]]; then
                    case "${4:-}" in
                        *NetworkSettings.Ports*) printf '%s\n' "$created_binding" | tr ';' '\n' ;;
                        *'|'*) printf '%s|%s|%s|%s\n' "$created_id" "$created_ownership" "$created_token" "$created_running" ;;
                        *) printf '%s %s\n' "$created_id" "$created_token" ;;
                    esac
                fi
                exit 0
            fi
        fi
        if [[ "${DOCKER_INSPECT_EXISTS:-0}" == "1" ]]; then
            if [[ "${3:-}" == "--format" ]]; then
                case "${4:-}" in
                    *NetworkSettings.Ports*) printf '127.0.0.1\n' ;;
                    *'|'*) printf '%s|true|11111111111111111111111111111111|true\n' "$DOCKER_RUN_ID" ;;
                    *) printf '%s 11111111111111111111111111111111\n' "$DOCKER_RUN_ID" ;;
                esac
            fi
            exit 0
        fi
        printf 'Error: no such container "%s"\n' "$requested_name" >&2
        exit 1
        ;;
    network)
        case "${2:-}" in
            inspect)
                if [[ "${DOCKER_NETWORK_INSPECT_FAIL:-0}" == "1" ]]; then
                    printf 'permission denied\n' >&2
                    exit 1
                fi
                if [[ "${DOCKER_NETWORK_INSPECT_FORMAT_INVALID:-0}" == "1" ]]; then
                    printf 'invalid inspection output\n'
                    exit 0
                fi
                requested_name="${!#}"
                if [[ -f "$DOCKER_NETWORK_STATE_FILE" ]]; then
                    IFS=' ' read -r network_name network_id network_ownership network_token < "$DOCKER_NETWORK_STATE_FILE"
                    if [[ "$requested_name" == "$network_name" ]]; then
                        if [[ "${3:-}" == "--format" ]]; then
                            case "${4:-}" in
                                *'|'*) printf '%s|%s|%s\n' "$network_id" "$network_ownership" "$network_token" ;;
                                *) printf '%s %s\n' "$network_id" "$network_token" ;;
                            esac
                            if [[ "${DOCKER_NETWORK_REPLACE_AFTER_INSPECT:-0}" == "1" ]]; then
                                printf '%s %s %s %s\n' "$network_name" "$DOCKER_REPLACEMENT_NETWORK_ID" replacement-owner replacement-launch-token > "$DOCKER_NETWORK_STATE_FILE"
                            fi
                        fi
                        exit 0
                    fi
                fi
                if [[ "${DOCKER_NETWORK_EXISTS:-0}" == "1" ]]; then
                    if [[ "${3:-}" == "--format" ]]; then
                        printf '%s|true|11111111111111111111111111111111\n' "$DOCKER_NETWORK_ID"
                    fi
                    exit 0
                fi
                printf 'Error: No such network: %s\n' "$requested_name" >&2
                exit 1
                ;;
            create)
                network_name="${!#}"
                network_ownership=""
                network_token=""
                for ((index = 1; index <= $#; index++)); do
                    if [[ "${!index}" == "--label" ]]; then
                        next=$((index + 1))
                        label="${!next}"
                        case "$label" in
                            io.opencode-containment.web-server=*)
                                network_ownership="${label#io.opencode-containment.web-server=}"
                                ;;
                            io.opencode-containment.web-launch-id=*)
                                network_token="${label#io.opencode-containment.web-launch-id=}"
                                ;;
                        esac
                    fi
                done
                if [[ "${DOCKER_NETWORK_CREATE_FOREIGN:-0}" == "1" ]]; then
                    printf '%s %s %s %s\n' "$network_name" "$DOCKER_REPLACEMENT_NETWORK_ID" foreign-owner foreign-launch-token > "$DOCKER_NETWORK_STATE_FILE"
                    exit 1
                fi
                printf '%s %s %s %s\n' "$network_name" "$DOCKER_NETWORK_ID" "$network_ownership" "$network_token" > "$DOCKER_NETWORK_STATE_FILE"
                if [[ -n "${DOCKER_NETWORK_SIGNAL:-}" ]]; then
                    kill "-$DOCKER_NETWORK_SIGNAL" "$PPID"
                fi
                exit 0
                ;;
            rm)
                requested_name="${!#}"
                [[ "${DOCKER_NETWORK_RM_FAIL:-0}" != "1" ]] || exit 1
                if [[ -f "$DOCKER_NETWORK_STATE_FILE" ]]; then
                    IFS=' ' read -r _ network_id _ _ < "$DOCKER_NETWORK_STATE_FILE"
                    [[ "$requested_name" != "$network_id" ]] || rm -f "$DOCKER_NETWORK_STATE_FILE"
                fi
                exit 0
                ;;
        esac
        ;;
    run)
        printf '%s\n' "$@" > "$DOCKER_LOG"
        container_name=""
        container_ownership=""
        launch_token=""
        publish_binding=""
        for ((index = 1; index <= $#; index++)); do
            case "${!index}" in
                --name)
                    next=$((index + 1))
                    container_name="${!next}"
                    ;;
                --label)
                    next=$((index + 1))
                    label="${!next}"
                    case "$label" in
                        io.opencode-containment.web-server=*)
                            container_ownership="${label#io.opencode-containment.web-server=}"
                            ;;
                        io.opencode-containment.web-launch-id=*)
                            launch_token="${label#io.opencode-containment.web-launch-id=}"
                            ;;
                    esac
                    ;;
                --publish)
                    next=$((index + 1))
                    publish_binding="${!next}"
                    publish_binding="${publish_binding%:*}"
                    publish_binding="${publish_binding%:*}"
                    ;;
            esac
        done
        if [[ "${DOCKER_RUN_FAIL_AFTER_CREATE:-0}" == "1" ]]; then
            if [[ "${DOCKER_RUN_FAIL_FOREIGN:-0}" == "1" ]]; then
                launch_token="${DOCKER_FOREIGN_LAUNCH_TOKEN:-foreign-launch-token}"
            fi
            printf '%s %s %s %s %s %s\n' "$container_name" "${DOCKER_RUN_ID}" "$container_ownership" "$launch_token" true "$publish_binding" > "$DOCKER_CREATED_CONTAINER_FILE"
            exit 1
        fi
        printf '%s %s %s %s %s %s\n' "$container_name" "${DOCKER_RUN_ID}" "$container_ownership" "$launch_token" true "$publish_binding" > "$DOCKER_CREATED_CONTAINER_FILE"
        printf '%s\n' "${DOCKER_RUN_ID}"
        ;;
    logs)
        printf 'test container log\n' >&2
        ;;
    rm)
        requested_id="${!#}"
        [[ "${DOCKER_RM_FAIL:-0}" != "1" ]] || exit 1
        if [[ -f "$DOCKER_CREATED_CONTAINER_FILE" ]]; then
            IFS=' ' read -r _ created_id _ _ _ _ < "$DOCKER_CREATED_CONTAINER_FILE"
            [[ "$requested_id" != "$created_id" ]] || rm -f "$DOCKER_CREATED_CONTAINER_FILE"
        fi
        ;;
esac
EOF
chmod +x "$FAKE_BIN/docker"

cat > "$FAKE_BIN/chmod" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${CHMOD_SIGNAL:-}" ]]; then
    kill "-$CHMOD_SIGNAL" "$PPID"
fi
exec /bin/chmod "$@"
EOF
chmod +x "$FAKE_BIN/chmod"

cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$CURL_EVENTS"

auth_config=""
for ((index = 1; index <= $#; index++)); do
    if [[ "${!index}" == "--config" ]]; then
        next=$((index + 1))
        auth_config="${!next}"
        break
    fi
done

if [[ -n "$auth_config" ]]; then
    [[ -f "$auth_config" ]] || exit 1
    [[ "$(stat -c '%a' "$auth_config")" == "600" ]] || exit 1
    IFS= read -r auth_line < "$auth_config"
    [[ "$auth_line" == user\ =\ * ]] || exit 1
    printf '%s' "${CURL_AUTH_STATUS:-200}"
else
    printf '%s' "${CURL_UNAUTH_STATUS:-401}"
fi
EOF
chmod +x "$FAKE_BIN/curl"

cat > "$FAKE_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${SLEEP_SIGNAL:-}" ]]; then
    kill "-$SLEEP_SIGNAL" "$PPID"
fi
exit 0
EOF
chmod +x "$FAKE_BIN/sleep"

run_launcher_with() {
    local launcher="$1"
    shift

    run_launcher_from_with "$WORKSPACE" "$launcher" "$@"
}

run_launcher_from_with() {
    local working_directory="$1" launcher="$2"
    shift 2

    (
        cd "$working_directory"
        PATH="$FAKE_BIN:$PATH" \
            DOCKER_LOG="$DOCKER_LOG" \
            DOCKER_EVENTS="$DOCKER_EVENTS" \
            DOCKER_CREATED_CONTAINER_FILE="$DOCKER_CREATED_CONTAINER_FILE" \
            DOCKER_NETWORK_STATE_FILE="$DOCKER_NETWORK_STATE_FILE" \
            DOCKER_INSPECT_EXISTS="${DOCKER_INSPECT_EXISTS:-0}" \
            DOCKER_CONTAINER_INSPECT_FAIL="${DOCKER_CONTAINER_INSPECT_FAIL:-0}" \
            DOCKER_CONTAINER_INSPECT_FORMAT_INVALID="${DOCKER_CONTAINER_INSPECT_FORMAT_INVALID:-0}" \
            DOCKER_NETWORK_EXISTS="${DOCKER_NETWORK_EXISTS:-0}" \
            DOCKER_NETWORK_INSPECT_FAIL="${DOCKER_NETWORK_INSPECT_FAIL:-0}" \
            DOCKER_NETWORK_INSPECT_FORMAT_INVALID="${DOCKER_NETWORK_INSPECT_FORMAT_INVALID:-0}" \
            DOCKER_NETWORK_CREATE_FOREIGN="${DOCKER_NETWORK_CREATE_FOREIGN:-0}" \
            DOCKER_NETWORK_SIGNAL="${DOCKER_NETWORK_SIGNAL:-}" \
            DOCKER_NETWORK_REPLACE_AFTER_INSPECT="${DOCKER_NETWORK_REPLACE_AFTER_INSPECT:-0}" \
            DOCKER_NETWORK_RM_FAIL="${DOCKER_NETWORK_RM_FAIL:-0}" \
            DOCKER_RM_FAIL="${DOCKER_RM_FAIL:-0}" \
            DOCKER_NETWORK_ID="$DOCKER_NETWORK_ID" \
            DOCKER_REPLACEMENT_NETWORK_ID="$DOCKER_REPLACEMENT_NETWORK_ID" \
            DOCKER_RUN_ID="${DOCKER_RUN_ID}" \
            DOCKER_SERVER_VERSION="${DOCKER_SERVER_VERSION:-28.0.0}" \
            DOCKER_RUN_FAIL_AFTER_CREATE="${DOCKER_RUN_FAIL_AFTER_CREATE:-0}" \
            DOCKER_RUN_FAIL_FOREIGN="${DOCKER_RUN_FAIL_FOREIGN:-0}" \
            DOCKER_FOREIGN_LAUNCH_TOKEN="${DOCKER_FOREIGN_LAUNCH_TOKEN:-}" \
            CURL_UNAUTH_STATUS="${CURL_UNAUTH_STATUS:-401}" \
            CURL_AUTH_STATUS="${CURL_AUTH_STATUS:-200}" \
            CURL_EVENTS="$CURL_EVENTS" \
            CHMOD_SIGNAL="${CHMOD_SIGNAL:-}" \
            SLEEP_SIGNAL="${SLEEP_SIGNAL:-}" \
            HOME="$TEST_HOME" \
            OPENCODE_CONTAINER_HOME="$CONTAINER_HOME" \
            "$launcher" "$@"
    )
}

run_launcher() {
    run_launcher_with "$LAUNCHER" "$@"
}

run_launcher_from() {
    local working_directory="$1"
    shift

    run_launcher_from_with "$working_directory" "$LAUNCHER" "$@"
}

reset_docker_artifacts() {
    rm -f "$DOCKER_LOG" "$DOCKER_EVENTS" "$DOCKER_CREATED_CONTAINER_FILE" "$DOCKER_NETWORK_STATE_FILE" "$CURL_EVENTS"
}

assert_no_temporary_web_files() {
    local temporary_files

    shopt -s nullglob
    temporary_files=("$credentials_dir"/.curl-auth.* "$credentials_dir"/.credentials.*)
    (( ${#temporary_files[@]} == 0 )) || fail "temporary credentials files were not removed"
    shopt -u nullglob
}

run_launcher auth ls > "$OUTPUT"
mapfile -t docker_args < "$DOCKER_LOG"
assert_command_tail opencode auth ls

reset_docker_artifacts
run_launcher start > "$OUTPUT"
mapfile -t docker_args < "$DOCKER_LOG"
assert_command_tail opencode start

reset_docker_artifacts
run_launcher_with "$LINKED_LAUNCHER" --web-server --web-port 4701 > "$OUTPUT"
mapfile -t docker_args < "$DOCKER_LOG"
workspace_hash="$(printf '%s' "$WORKSPACE" | cksum)"
workspace_hash="${workspace_hash%% *}"
container_name="opencode-web-workspace-${workspace_hash}-4701"
network_name="${container_name}-network"
credentials_dir="$CONTAINER_HOME/web-server"
credentials_file="$credentials_dir/${container_name}.credentials"
container_id="$DOCKER_RUN_ID"

assert_arg_pair --detach --name
assert_arg_pair --name "$container_name"
assert_arg_pair --publish "127.0.0.1:4701:4701"
assert_arg_pair --volume "$credentials_file:/tmp/opencode-web-credentials:ro"
assert_arg_pair --volume "$SCRIPT_DIR/scripts/web-server-entrypoint.sh:/tmp/opencode-web-entrypoint:ro"
assert_arg_pair --network "$network_name"
assert_arg_pair --entrypoint /bin/sh
assert_arg_pair --label "io.opencode-containment.web-server=true"
assert_command_tail /tmp/opencode-web-entrypoint 4701
assert_no_server_env
assert_event_pattern "network create --driver bridge --label io.opencode-containment.web-server=true --label io.opencode-containment.web-launch-id=* $network_name"
assert_line "  URL: http://127.0.0.1:4701" "$OUTPUT"
assert_line "  Bind: loopback" "$OUTPUT"
assert_line "  Basic Auth credentials: $credentials_file" "$OUTPUT"
assert_line "  Container ID: $container_id" "$OUTPUT"
assert_line "  Network: $network_name" "$OUTPUT"
assert_line "  Stop and remove: opencode-container --workspace $WORKSPACE --web-server stop --web-port 4701" "$OUTPUT"

[[ "$(stat -c '%a' "$credentials_dir")" == "700" ]] || fail "credentials directory is not mode 0700"
[[ "$(stat -c '%a' "$credentials_file")" == "600" ]] || fail "credentials file is not mode 0600"
credential_lines=()
mapfile -t credential_lines < "$credentials_file"
[[ ${#credential_lines[@]} -eq 2 ]] || fail "credentials file has unexpected line count"
[[ "${credential_lines[0]}" =~ ^OPENCODE_SERVER_USERNAME=(opencode-[0-9a-f]{16})$ ]] || fail "invalid generated username"
[[ "${credential_lines[1]}" =~ ^OPENCODE_SERVER_PASSWORD=([0-9a-f]{64})$ ]] || fail "invalid generated password"
valid_credentials="$(<"$credentials_file")"
assert_no_temporary_web_files

reset_docker_artifacts
run_launcher --web-server start --web-port 4701 --network-accessible > "$OUTPUT" 2>&1
mapfile -t docker_args < "$DOCKER_LOG"
assert_arg_pair --publish "0.0.0.0:4701:4701"
assert_arg_pair --label "io.opencode-containment.web-server=true"
assert_line "WARNING: --network-accessible exposes this HTTP server and its Basic Auth credentials on your LAN. The server can access your workspace and provider credentials." "$OUTPUT"
assert_line "  Bind: network-accessible" "$OUTPUT"

reset_docker_artifacts
printf '%s %s %s %s\n' "$network_name" "$DOCKER_REPLACEMENT_NETWORK_ID" foreign-owner foreign-launch-token > "$DOCKER_NETWORK_STATE_FILE"
if run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "foreign same-name network should prevent launch"
fi
[[ ! -e "$DOCKER_LOG" ]] || fail "Docker run should not execute with a foreign network"
assert_line "Error: Refusing to use unowned web server network '$network_name'." "$OUTPUT"
assert_no_event "network rm $DOCKER_REPLACEMENT_NETWORK_ID"
[[ "$(<"$credentials_file")" == "$valid_credentials" ]] || fail "valid credentials should be reused"

reset_docker_artifacts
if DOCKER_INSPECT_EXISTS=1 run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "existing web container should prevent launch"
fi
[[ ! -e "$DOCKER_LOG" ]] || fail "Docker run should not execute when the container exists"
assert_line "Error: Web server container '$container_name' already exists." "$OUTPUT"
assert_line "Stop and remove it with: opencode-container --workspace $WORKSPACE --web-server stop --web-port 4701" "$OUTPUT"

reset_docker_artifacts
if DOCKER_SERVER_VERSION=27.5.1 run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "Docker Engine older than 28 should prevent web server launch"
fi
[[ ! -e "$DOCKER_LOG" ]] || fail "Docker run should not execute on an unsupported Docker Engine"
assert_line "Error: Docker Engine 28 or later is required for --web-server because older Docker versions can expose localhost-published ports to other hosts on the local network." "$OUTPUT"

lifecycle_workspace="$WORKSPACE/deleted workspace"
mkdir "$lifecycle_workspace"
reset_docker_artifacts
run_launcher --workspace "$lifecycle_workspace" --web-server --web-port 4702 > "$OUTPUT"
printf -v lifecycle_workspace_argument '%q' "$lifecycle_workspace"
assert_line "  Stop and remove: opencode-container --workspace $lifecycle_workspace_argument --web-server stop --web-port 4702" "$OUTPUT"
rm -rf "$lifecycle_workspace"
run_launcher_from "$TEST_DIR" --workspace "$lifecycle_workspace" --web-server status --web-port 4702 > "$OUTPUT"
assert_line "  Service: running" "$OUTPUT"
run_launcher_from "$TEST_DIR" --workspace "$lifecycle_workspace" --web-server stop --web-port 4702 > "$OUTPUT"
assert_event "rm -f $DOCKER_RUN_ID"

write_web_container_state() {
    printf '%s %s %s %s %s %s\n' "$@" > "$DOCKER_CREATED_CONTAINER_FILE"
}

write_web_network_state() {
    printf '%s %s %s %s\n' "$@" > "$DOCKER_NETWORK_STATE_FILE"
}

reset_docker_artifacts
run_launcher --web-server status --web-port 4701 > "$OUTPUT"
assert_line "  Service: absent" "$OUTPUT"
assert_line "  Bind: unavailable" "$OUTPUT"
assert_line "  Container name: $container_name" "$OUTPUT"
assert_line "  Container ID: absent" "$OUTPUT"
assert_line "  Network name: $network_name" "$OUTPUT"
assert_line "  Network ID: absent" "$OUTPUT"
assert_line "  Credentials: present" "$OUTPUT"
assert_no_line "${credential_lines[0]}" "$OUTPUT"
assert_no_line "${credential_lines[1]}" "$OUTPUT"
[[ ! -e "$CURL_EVENTS" ]] || fail "status must not make HTTP requests"

legacy_launch_token="11111111111111111111111111111111"
legacy_container_id="1212121212121212121212121212121212121212121212121212121212121212"
legacy_network_id="1313131313131313131313131313131313131313131313131313131313131313"
write_web_container_state "$container_name" "$legacy_container_id" true "$legacy_launch_token" true "127.0.0.1"
write_web_network_state "$network_name" "$legacy_network_id" true "$legacy_launch_token"
run_launcher --web-server status --web-port 4701 > "$OUTPUT"
assert_line "  Service: running" "$OUTPUT"
assert_line "  Bind: loopback" "$OUTPUT"
assert_line "  Container ID: $legacy_container_id" "$OUTPUT"
assert_line "  Network ID: $legacy_network_id" "$OUTPUT"
[[ ! -e "$CURL_EVENTS" ]] || fail "status must not make authenticated HTTP requests"

write_web_container_state "$container_name" "$legacy_container_id" legacy "$legacy_launch_token" true "0.0.0.0"
write_web_network_state "$network_name" "$legacy_network_id" legacy "$legacy_launch_token"
run_launcher --web-server status --web-port 4701 > "$OUTPUT"
assert_line "  Bind: network-accessible" "$OUTPUT"
assert_line "  Container ID: $legacy_container_id" "$OUTPUT"
assert_line "  Network ID: $legacy_network_id" "$OUTPUT"

write_web_container_state "$container_name" "$legacy_container_id" true "$legacy_launch_token" true "127.0.0.1;::1"
run_launcher --web-server status --web-port 4701 > "$OUTPUT"
assert_line "  Bind: loopback" "$OUTPUT"

write_web_container_state "$container_name" "$legacy_container_id" true "$legacy_launch_token" true "127.0.0.1;::"
run_launcher --web-server status --web-port 4701 > "$OUTPUT"
assert_line "  Bind: network-accessible" "$OUTPUT"

write_web_container_state "$container_name" "$legacy_container_id" true "$legacy_launch_token" true "127.0.0.1;192.0.2.10"
run_launcher --web-server status --web-port 4701 > "$OUTPUT"
assert_line "  Bind: network-accessible" "$OUTPUT"

write_web_container_state "$container_name" "$legacy_container_id" true "$legacy_launch_token" false "127.0.0.1"
run_launcher --web-server status --web-port 4701 > "$OUTPUT"
assert_line "  Service: stopped" "$OUTPUT"
assert_line "  Bind: unavailable" "$OUTPUT"

reset_docker_artifacts
write_web_container_state "$container_name" "$legacy_container_id" true "$legacy_launch_token" true "127.0.0.1"
write_web_network_state "$network_name" "$legacy_network_id" true "$legacy_launch_token"
if DOCKER_CONTAINER_INSPECT_FAIL=1 run_launcher --web-server status --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "container inspection failure should fail status"
fi
assert_line "Error: Could not inspect web server container '$container_name': permission denied" "$OUTPUT"

if DOCKER_CONTAINER_INSPECT_FORMAT_INVALID=1 run_launcher --web-server status --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "container inspection format failure should fail status"
fi
assert_line "Error: Web server container inspection returned an invalid format for '$container_name'." "$OUTPUT"

if DOCKER_NETWORK_INSPECT_FAIL=1 run_launcher --web-server status --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "network inspection failure should fail status"
fi
assert_line "Error: Could not inspect web server network '$network_name': permission denied" "$OUTPUT"

if DOCKER_NETWORK_INSPECT_FORMAT_INVALID=1 run_launcher --web-server stop --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "network inspection format failure should fail stop"
fi
assert_no_event "rm -f $legacy_container_id"
assert_no_event "network rm $legacy_network_id"
assert_line "Error: Web server network inspection returned an invalid format for '$network_name'." "$OUTPUT"

printf 'not credentials\n' > "$credentials_file"
chmod 600 "$credentials_file"
run_launcher --web-server status --web-port 4701 > "$OUTPUT"
assert_line "  Credentials: present" "$OUTPUT"
[[ ! -e "$CURL_EVENTS" ]] || fail "status must not read credentials through an HTTP request"
printf '%s\n' "$valid_credentials" > "$credentials_file"
chmod 600 "$credentials_file"

reset_docker_artifacts
write_web_container_state "$container_name" "$legacy_container_id" legacy "$legacy_launch_token" true "127.0.0.1"
write_web_network_state "$network_name" "$legacy_network_id" legacy "$legacy_launch_token"
run_launcher --web-server stop --web-port 4701 > "$OUTPUT"
assert_event "rm -f $legacy_container_id"
assert_event "network rm $legacy_network_id"
assert_line "Removed web server container '$legacy_container_id'." "$OUTPUT"
assert_line "Removed web server network '$legacy_network_id'." "$OUTPUT"
assert_line "Web server credentials preserved: present ($credentials_file)." "$OUTPUT"
[[ "$(<"$credentials_file")" == "$valid_credentials" ]] || fail "stop should preserve credentials"

reset_docker_artifacts
write_web_container_state "$container_name" "$legacy_container_id" true "$legacy_launch_token" true "127.0.0.1"
write_web_network_state "$network_name" "$legacy_network_id" true "$legacy_launch_token"
if DOCKER_NETWORK_RM_FAIL=1 run_launcher --web-server stop --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "network removal failure should fail stop"
fi
assert_event "rm -f $legacy_container_id"
assert_event "network rm $legacy_network_id"
assert_no_event "network disconnect $legacy_network_id"
assert_line "Warning: Could not remove web server network '$legacy_network_id'; attached endpoints were not force-disconnected." "$OUTPUT"

reset_docker_artifacts
foreign_container_id="1414141414141414141414141414141414141414141414141414141414141414"
foreign_network_id="1515151515151515151515151515151515151515151515151515151515151515"
write_web_container_state "$container_name" "$foreign_container_id" foreign foreign-token true "0.0.0.0"
write_web_network_state "$network_name" "$foreign_network_id" foreign foreign-token
if run_launcher --web-server stop --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "stop should reject unowned resources"
fi
assert_no_event "rm -f $foreign_container_id"
assert_no_event "network rm $foreign_network_id"
assert_line "Error: Refusing to remove unowned container '$container_name'." "$OUTPUT"
assert_line "Error: Refusing to remove unowned network '$network_name'." "$OUTPUT"
[[ "$(<"$credentials_file")" == "$valid_credentials" ]] || fail "stop should preserve credentials for unowned resources"
run_launcher --web-server status --web-port 4701 > "$OUTPUT"
assert_line "  Service: absent" "$OUTPUT"
assert_line "  Container ID: unmanaged" "$OUTPUT"
assert_line "  Network ID: unmanaged" "$OUTPUT"

reset_docker_artifacts
OPENCODE_NETWORK_ACCESSIBLE=1 run_launcher --web-server start --web-port 4701 > "$OUTPUT"
mapfile -t docker_args < "$DOCKER_LOG"
assert_arg_pair --publish "127.0.0.1:4701:4701"

rm -f "$DOCKER_LOG" "$DOCKER_EVENTS"
if run_launcher --web-server --web-port > "$OUTPUT" 2>&1; then
    fail "missing --web-port value should fail"
fi
assert_line "Error: --web-port requires a port value." "$OUTPUT"

if run_launcher --web-server --web-port --sync-config > "$OUTPUT" 2>&1; then
    fail "option after --web-port should not be accepted as its value"
fi
assert_line "Error: --web-port requires a port value." "$OUTPUT"

rm -f "$DOCKER_LOG" "$DOCKER_EVENTS"
if run_launcher --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "--web-port without --web-server should fail"
fi
assert_line "Error: --web-port requires --web-server." "$OUTPUT"

if run_launcher --network-accessible > "$OUTPUT" 2>&1; then
    fail "--network-accessible without --web-server should fail"
fi
assert_line "Error: --network-accessible requires --web-server start." "$OUTPUT"

if run_launcher --web-server stop --network-accessible > "$OUTPUT" 2>&1; then
    fail "--network-accessible with stop should fail"
fi
assert_line "Error: --network-accessible is only valid with --web-server start." "$OUTPUT"

if run_launcher --web-server restart > "$OUTPUT" 2>&1; then
    fail "unknown web server command should fail"
fi
assert_line "Error: Unknown web server command 'restart'. Use start, stop, or status." "$OUTPUT"

assert_invalid_credentials() {
    local expected="$1"

    reset_docker_artifacts
    if run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
        fail "invalid credentials should prevent launch"
    fi
    [[ ! -e "$DOCKER_LOG" ]] || fail "Docker run should not execute with invalid credentials"
    assert_line "$expected" "$OUTPUT"
}

printf 'not credentials\n' > "$credentials_file"
chmod 600 "$credentials_file"
assert_invalid_credentials "Error: Web server credentials file is malformed: $credentials_file"

printf '%s' "$valid_credentials" > "$credentials_file"
chmod 600 "$credentials_file"
assert_invalid_credentials "Error: Web server credentials file is malformed: $credentials_file"

printf '%s\n' "${valid_credentials%?}g" > "$credentials_file"
chmod 600 "$credentials_file"
assert_invalid_credentials "Error: Web server credentials file is malformed: $credentials_file"

rm -f "$credentials_file"
ln -s "$TEST_DIR/not-credentials" "$credentials_file"
assert_invalid_credentials "Error: Web server credentials path is not a regular file: $credentials_file"

rm -f "$credentials_file"
mkfifo "$credentials_file"
assert_invalid_credentials "Error: Web server credentials path is not a regular file: $credentials_file"

rm -f "$credentials_file"
printf '%s\n' "$valid_credentials" > "$credentials_file"
chmod 644 "$credentials_file"
assert_invalid_credentials "Error: Web server credentials file must have mode 0600: $credentials_file"

printf '%s\n' "$valid_credentials" > "$credentials_file"
chmod 600 "$credentials_file"
reset_docker_artifacts
failed_container_id="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
if DOCKER_RUN_ID="$failed_container_id" DOCKER_RUN_FAIL_AFTER_CREATE=1 run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "Docker run failure after container creation should fail the launch"
fi
assert_line "Error: Could not start web server container '$container_name'." "$OUTPUT"
assert_line "Web server logs for '$failed_container_id':" "$OUTPUT"
assert_event "logs $failed_container_id"
assert_event "rm -f $failed_container_id"
assert_no_event "rm -f $container_name"
assert_event "network rm $DOCKER_NETWORK_ID"

reset_docker_artifacts
foreign_container_id="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
if DOCKER_RUN_ID="$foreign_container_id" DOCKER_RUN_FAIL_AFTER_CREATE=1 DOCKER_RUN_FAIL_FOREIGN=1 run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "Docker run failure with a concurrent container should fail the launch"
fi
assert_line "Error: Could not start web server container '$container_name'." "$OUTPUT"
assert_no_event "logs $foreign_container_id"
assert_no_event "rm -f $foreign_container_id"
assert_event "network rm $DOCKER_NETWORK_ID"

reset_docker_artifacts
signal_container_id="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
if DOCKER_RUN_ID="$signal_container_id" CURL_AUTH_STATUS=500 SLEEP_SIGNAL=TERM run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "TERM during readiness should fail the launch"
fi
assert_line "Web server logs for '$signal_container_id':" "$OUTPUT"
assert_event "logs $signal_container_id"
assert_event "rm -f $signal_container_id"
assert_event "network rm $DOCKER_NETWORK_ID"
assert_no_temporary_web_files

reset_docker_artifacts
if CURL_AUTH_STATUS=500 run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "failed authentication check should fail the launch"
fi
assert_no_line "OpenCode web server is running." "$OUTPUT"
assert_line "Error: Web server readiness/authentication check failed (unauthenticated status: 401; authenticated status: 500)." "$OUTPUT"
assert_line "Web server logs for '$container_id':" "$OUTPUT"
assert_event "logs $container_id"
assert_event "rm -f $container_id"
assert_event "network rm $DOCKER_NETWORK_ID"
assert_no_temporary_web_files

reset_docker_artifacts
if DOCKER_NETWORK_SIGNAL=TERM run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "TERM during network creation should fail the launch"
fi
[[ ! -e "$DOCKER_LOG" ]] || fail "Docker run should not execute after TERM during network creation"
assert_event "network rm $DOCKER_NETWORK_ID"
[[ ! -e "$DOCKER_NETWORK_STATE_FILE" ]] || fail "network should be removed after TERM during creation"

reset_docker_artifacts
if DOCKER_NETWORK_CREATE_FOREIGN=1 CURL_AUTH_STATUS=500 run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "readiness failure with a concurrent network should fail the launch"
fi
assert_no_event "network rm $DOCKER_NETWORK_ID"

rm -f "$credentials_file"
reset_docker_artifacts
if CHMOD_SIGNAL=TERM run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "TERM during credential generation should fail the launch"
fi
assert_no_temporary_web_files

printf '%s\n' "$valid_credentials" > "$credentials_file"
chmod 600 "$credentials_file"
reset_docker_artifacts
if DOCKER_NETWORK_REPLACE_AFTER_INSPECT=1 CURL_AUTH_STATUS=500 run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "readiness failure with a replaced network should fail the launch"
fi
assert_event "network rm $DOCKER_NETWORK_ID"
[[ -e "$DOCKER_NETWORK_STATE_FILE" ]] || fail "replacement network should not be removed"

reset_docker_artifacts
int_signal_container_id="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
if DOCKER_RUN_ID="$int_signal_container_id" CURL_AUTH_STATUS=500 SLEEP_SIGNAL=INT run_launcher --web-server --web-port 4701 > "$OUTPUT" 2>&1; then
    fail "INT during readiness should fail the launch"
fi
assert_event "rm -f $int_signal_container_id"
assert_event "network rm $DOCKER_NETWORK_ID"
assert_no_temporary_web_files

reset_docker_artifacts
set +e
run_launcher --web-server --web-port 4701 2> "$OUTPUT" | true
launcher_status="${PIPESTATUS[0]}"
set -e
((launcher_status != 0)) || fail "broken pipe while reporting launch details should fail the launch"
assert_line "Web server logs for '$container_id':" "$OUTPUT"
assert_event "rm -f $container_id"
assert_event "network rm $DOCKER_NETWORK_ID"

echo "Launcher tests passed."
