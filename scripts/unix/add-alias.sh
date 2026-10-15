#!/bin/sh
set -eu

fail() { printf '%s\n' "error_code=$1" "action=$2" >&2; exit 1; }
alias_name= target_host= remote_user= private_key= proxy_jump= identity_agent= transport=direct port=22 apply=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --alias) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --alias."; alias_name=$2; shift 2 ;;
    --host) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --host."; target_host=$2; shift 2 ;;
    --user) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --user."; remote_user=$2; shift 2 ;;
    --key) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --key."; private_key=$2; shift 2 ;;
    --port) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --port."; port=$2; shift 2 ;;
    --proxy-jump) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --proxy-jump."; proxy_jump=$2; shift 2 ;;
    --identity-agent) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --identity-agent."; identity_agent=$2; shift 2 ;;
    --transport) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --transport."; transport=$2; shift 2 ;;
    --apply) apply=true; shift ;;
    *) fail invalid_arguments "Use alias, endpoint, account, key, and optional route arguments." ;;
  esac
done
[ -n "$alias_name" ] && [ -n "$target_host" ] && [ -n "$remote_user" ] && [ -n "$private_key" ] || fail invalid_arguments "Provide every required value."
printf '%s' "$alias_name" | grep -Eq '^[A-Za-z0-9._-]+$' || fail invalid_alias "Use letters, digits, dots, underscores, or hyphens."
printf '%s' "$target_host" | grep -Eq '^[A-Za-z0-9._:%-]+$' || fail invalid_host "Use a valid hostname, IPv4 address, or IPv6 address."
printf '%s' "$remote_user" | grep -Eq '^[A-Za-z0-9._@\\-]+$' || fail invalid_user "Use the verified remote account name."
printf '%s' "$port" | grep -Eq '^[0-9]+$' || fail invalid_port "Use a numeric TCP port."
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || fail invalid_port "Use a TCP port from 1 through 65535."
printf '%s' "$transport" | grep -Eq '^[A-Za-z0-9._-]+$' || fail invalid_transport "Use a short transport label without spaces."
[ -z "$proxy_jump" ] || printf '%s' "$proxy_jump" | grep -Eq '^[^[:space:]#]+$' || fail invalid_proxy_jump "Use an SSH alias or a compact OpenSSH jump specification."
[ -z "$identity_agent" ] || printf '%s' "$identity_agent" | grep -Eq '^[^[:space:]#"]+$' || fail invalid_identity_agent "Use an agent socket path without spaces, quotes, or #."
[ -f "$private_key" ] || fail missing_private_key "Select an existing local private key, or its .pub file when the key lives only in an agent."
ssh_dir=$HOME/.ssh
config_file=$ssh_dir/config
if [ -f "$config_file" ] && awk -v wanted="$alias_name" '$1 == "Host" { for (i=2;i<=NF;i++) if ($i == wanted) found=1 } END { exit(found ? 0 : 1) }' "$config_file"; then
  printf '%s\n' schema_version=1 "action=$([ "$apply" = true ] && printf apply || printf preview)" status=already_exists "alias=$alias_name" "config=$config_file"
  exit 0
fi
emit_status() { printf '%s\n' schema_version=1 "action=$1" "status=$2" "alias=$alias_name" "transport=$transport" "host=$target_host" "port=$port" "proxy_jump=${proxy_jump:-none}" "identity_agent=${identity_agent:-default}" "user=$remote_user" "key=$private_key" "config=$config_file"; }
if [ "$apply" = false ]; then emit_status preview would_add; exit 0; fi
mkdir -p "$ssh_dir"; chmod 700 "$ssh_dir"; touch "$config_file"; chmod 600 "$config_file"
{
  printf '\nHost %s\n  HostName %s\n  Port %s\n  User %s\n  IdentityFile "%s"\n  IdentitiesOnly yes\n  ForwardAgent no\n' "$alias_name" "$target_host" "$port" "$remote_user" "$private_key"
  [ -z "$identity_agent" ] || printf '  IdentityAgent %s\n' "$identity_agent"
  [ -z "$proxy_jump" ] || printf '  ProxyJump %s\n' "$proxy_jump"
} >> "$config_file"
emit_status apply added
