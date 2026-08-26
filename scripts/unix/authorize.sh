#!/bin/sh
set -eu

fail() { printf '%s\n' "error_code=$1" "action=$2" >&2; exit 1; }
target_os= target_host= remote_user= public_key= proxy_jump= transport=direct port=22 apply=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target-os) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --target-os."; target_os=$2; shift 2 ;;
    --host) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --host."; target_host=$2; shift 2 ;;
    --user) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --user."; remote_user=$2; shift 2 ;;
    --public-key) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --public-key."; public_key=$2; shift 2 ;;
    --port) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --port."; port=$2; shift 2 ;;
    --proxy-jump) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --proxy-jump."; proxy_jump=$2; shift 2 ;;
    --transport) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --transport."; transport=$2; shift 2 ;;
    --apply) apply=true; shift ;;
    *) fail invalid_arguments "Use target, endpoint, account, public key, and optional route arguments." ;;
  esac
done
case "$target_os" in macos|linux|windows) ;; *) fail invalid_target_os "Use macos, linux, or windows." ;; esac
[ -n "$target_host" ] && [ -n "$remote_user" ] && [ -f "$public_key" ] || fail invalid_arguments "Resolve host, user, and an existing public key."
printf '%s' "$port" | grep -Eq '^[0-9]+$' || fail invalid_port "Use a numeric TCP port."
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || fail invalid_port "Use a TCP port from 1 through 65535."
printf '%s' "$target_host" | grep -Eq '^[A-Za-z0-9._:%-]+$' || fail invalid_host "Use a valid hostname, IPv4 address, or IPv6 address."
printf '%s' "$remote_user" | grep -Eq '^[A-Za-z0-9._@\\-]+$' || fail invalid_user "Use the verified remote account name."
printf '%s' "$transport" | grep -Eq '^[A-Za-z0-9._-]+$' || fail invalid_transport "Use a short transport label without spaces."
[ -z "$proxy_jump" ] || printf '%s' "$proxy_jump" | grep -Eq '^[^[:space:]#]+$' || fail invalid_proxy_jump "Use an SSH alias or a compact OpenSSH jump specification."
fingerprint=$(ssh-keygen -lf "$public_key") || fail invalid_public_key "Inspect or replace the selected public key."
printf '%s\n' schema_version=1 "action=$([ "$apply" = true ] && printf apply || printf preview)" "status=$([ "$apply" = true ] && printf authorizing || printf would_authorize)" "target_os=$target_os" "transport=$transport" "target=$target_host" "port=$port" "proxy_jump=${proxy_jump:-none}" "user=$remote_user" "public_key=$public_key" "fingerprint=$fingerprint" requires=interactive_remote_authentication
[ "$apply" = true ] || exit 0

for command_name in ssh scp; do command -v "$command_name" >/dev/null 2>&1 || fail missing_dependency "Install '$command_name' through machine bootstrap."; done
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
payload_root=$(CDPATH= cd -- "$script_dir/../../payloads" && pwd)
copy_payloads() {
  if [ -n "$proxy_jump" ]; then scp -P "$port" -o ProxyJump="$proxy_jump" -o IdentityAgent=none -o IdentitiesOnly=yes "$@" "$remote_user@$target_host:"
  else scp -P "$port" -o IdentityAgent=none -o IdentitiesOnly=yes "$@" "$remote_user@$target_host:"; fi
}
run_remote() {
  if [ -n "$proxy_jump" ]; then ssh -p "$port" -J "$proxy_jump" -o IdentityAgent=none -o IdentitiesOnly=yes "$remote_user@$target_host" "$1"
  else ssh -p "$port" -o IdentityAgent=none -o IdentitiesOnly=yes "$remote_user@$target_host" "$1"; fi
}
if [ "$target_os" = windows ]; then
  copy_payloads "$public_key" "$payload_root/authorize-windows.ps1" || fail initial_auth_failed "Retry interactively with the verified account password."
  run_remote "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\\authorize-windows.ps1 '$(basename "$public_key")'" || fail authorization_failed "Use an elevated Windows session if the account uses administrators_authorized_keys."
elif command -v ssh-copy-id >/dev/null 2>&1; then
  if [ -n "$proxy_jump" ]; then ssh-copy-id -p "$port" -o ProxyJump="$proxy_jump" -o IdentityAgent=none -o IdentitiesOnly=yes -i "$public_key" "$remote_user@$target_host"
  else ssh-copy-id -p "$port" -o IdentityAgent=none -o IdentitiesOnly=yes -i "$public_key" "$remote_user@$target_host"; fi || fail initial_auth_failed "Retry interactively with the verified account password."
else
  copy_payloads "$public_key" "$payload_root/authorize-unix.sh" || fail initial_auth_failed "Retry interactively with the verified account password."
  key_name=$(basename "$public_key")
  run_remote "/bin/sh \"\$HOME/authorize-unix.sh\" \"\$HOME/$key_name\"" || fail authorization_failed "Inspect the remote home directory and authorized_keys permissions."
fi
printf '%s\n' schema_version=1 action=apply status=authorized "transport=$transport" "target=$target_host" "port=$port" "proxy_jump=${proxy_jump:-none}" "user=$remote_user"
