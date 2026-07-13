#!/bin/sh
set -eu

credentials_file="/tmp/opencode-web-credentials"

fail() {
    echo "Error: Web server credentials are malformed." >&2
    exit 1
}

[ "$#" -eq 1 ] || fail
[ -f "$credentials_file" ] && [ ! -L "$credentials_file" ] || fail

exec 3< "$credentials_file"
IFS= read -r username_line <&3 || fail
IFS= read -r password_line <&3 || fail
if IFS= read -r extra_line <&3; then
    fail
fi
exec 3<&-

case "$username_line" in
    OPENCODE_SERVER_USERNAME=*) username=${username_line#OPENCODE_SERVER_USERNAME=} ;;
    *) fail ;;
esac
case "$password_line" in
    OPENCODE_SERVER_PASSWORD=*) password=${password_line#OPENCODE_SERVER_PASSWORD=} ;;
    *) fail ;;
esac

[ "${#username}" -eq 25 ] || fail
username_suffix=${username#opencode-}
[ "$username_suffix" != "$username" ] || fail
case "$username_suffix" in *[!0-9a-f]*) fail ;; esac
[ "${#password}" -eq 64 ] || fail
case "$password" in ''|*[!0-9a-f]*) fail ;; esac

export OPENCODE_SERVER_USERNAME="$username"
export OPENCODE_SERVER_PASSWORD="$password"
exec opencode web --hostname 0.0.0.0 --port "$1"
