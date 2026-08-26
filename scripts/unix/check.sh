#!/bin/sh
set -eu

fail() { printf '%s\n' "error_code=$1" "action=$2" >&2; exit 1; }
target_host= remote_user= private_key= ssh_alias= proxy_jump= transport=direct port=22
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --host."; target_host=$2; shift 2 ;;
    --user) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --user."; remote_user=$2; shift 2 ;;
    --key) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --key."; private_key=$2; shift 2 ;;
    --alias) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --alias."; ssh_alias=$2; shift 2 ;;
    --port) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --port."; port=$2; shift 2 ;;
    --proxy-jump) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --proxy-jump."; proxy_jump=$2; shift 2 ;;
    --transport) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --transport."; transport=$2; shift 2 ;;
    *) fail invalid_arguments "Use --alias NAME or --host HOST --user USER --key PRIVATE_KEY with optional route arguments." ;;
  esac
done
for command_name in ssh grep awk; do command -v "$command_name" >/dev/null 2>&1 || fail missing_dependency "Install or enable '$command_name' through machine bootstrap."; done

if [ -n "$ssh_alias" ]; then
  [ -z "$target_host$remote_user$private_key$proxy_jump" ] && [ "$port" = 22 ] && [ "$transport" = direct ] || fail invalid_arguments "Do not combine --alias with endpoint or route arguments."
  effective_config=$(ssh -G "$ssh_alias" 2>/dev/null) || fail invalid_alias "Inspect the SSH config entry for '$ssh_alias'."
  target_host=$(printf '%s\n' "$effective_config" | awk '$1 == "hostname" { print $2; exit }')
  remote_user=$(printf '%s\n' "$effective_config" | awk '$1 == "user" { print $2; exit }')
  private_key=$(printf '%s\n' "$effective_config" | awk '$1 == "identityfile" { print $2; exit }')
  port=$(printf '%s\n' "$effective_config" | awk '$1 == "port" { print $2; exit }')
  proxy_jump=$(printf '%s\n' "$effective_config" | awk '$1 == "proxyjump" { print $2; exit }')
  [ "$proxy_jump" = none ] && proxy_jump=
  transport=ssh-config
  case "$private_key" in '~/'*) private_key=$HOME/${private_key#\~/} ;; esac
else
  [ -n "$target_host" ] && [ -n "$remote_user" ] && [ -n "$private_key" ] || fail invalid_arguments "Provide --host HOST --user USER --key PRIVATE_KEY."
fi
printf '%s' "$port" | grep -Eq '^[0-9]+$' || fail invalid_port "Use a numeric TCP port."
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || fail invalid_port "Use a TCP port from 1 through 65535."
printf '%s' "$target_host" | grep -Eq '^[A-Za-z0-9._:%-]+$' || fail invalid_host "Use a valid hostname, IPv4 address, or IPv6 address."
printf '%s' "$remote_user" | grep -Eq '^[A-Za-z0-9._@\\-]+$' || fail invalid_user "Use the verified remote account name."
printf '%s' "$transport" | grep -Eq '^[A-Za-z0-9._-]+$' || fail invalid_transport "Use a short transport label without spaces."
[ -z "$proxy_jump" ] || printf '%s' "$proxy_jump" | grep -Eq '^[^[:space:]#]+$' || fail invalid_proxy_jump "Use an SSH alias or a compact OpenSSH jump specification."
[ -f "$private_key" ] || fail missing_private_key "Select an existing local private key."

ssh_key_test() {
  if [ -n "$ssh_alias" ]; then ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$ssh_alias" 'exit 0'
  elif [ -n "$proxy_jump" ]; then ssh -p "$port" -J "$proxy_jump" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$private_key" "$remote_user@$target_host" 'exit 0'
  else ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$private_key" "$remote_user@$target_host" 'exit 0'; fi
}
ssh_password_probe() {
  if [ -n "$ssh_alias" ]; then ssh -vv -o BatchMode=yes -o ConnectTimeout=10 -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive "$ssh_alias" 'exit 0'
  elif [ -n "$proxy_jump" ]; then ssh -vv -p "$port" -J "$proxy_jump" -o BatchMode=yes -o ConnectTimeout=10 -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive -o IdentitiesOnly=yes -i "$private_key" "$remote_user@$target_host" 'exit 0'
  else ssh -vv -p "$port" -o BatchMode=yes -o ConnectTimeout=10 -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive -o IdentitiesOnly=yes -i "$private_key" "$remote_user@$target_host" 'exit 0'; fi
}

printf '%s\n' schema_version=1 "transport=$transport" "target=$target_host" "port=$port" "proxy_jump=${proxy_jump:-none}" "user=$remote_user" "key=$private_key"
if [ -n "$proxy_jump" ]; then
  printf '%s\n' ssh_port=proxied
else
  command -v nc >/dev/null 2>&1 || fail missing_dependency "Install or enable 'nc' through machine bootstrap."
  if [ "$(uname -s)" = Darwin ]; then port_open=$(nc -z -G 5 -w 5 "$target_host" "$port" >/dev/null 2>&1 && printf yes || printf no)
  else port_open=$(nc -z -w 5 "$target_host" "$port" >/dev/null 2>&1 && printf yes || printf no); fi
  if [ "$port_open" = no ]; then printf '%s\n' ssh_port=closed key_auth=not_checked password_auth=not_checked; exit 0; fi
  printf '%s\n' ssh_port=open
fi
if ssh_key_test >/dev/null 2>&1; then printf '%s\n' key_auth=ok; else printf '%s\n' key_auth=missing; fi
authentication_output=$(ssh_password_probe 2>&1 || true)
if printf '%s\n' "$authentication_output" | grep -Eq 'Authentications that can continue:.*(password|keyboard-interactive)'; then printf '%s\n' password_auth=enabled
elif printf '%s\n' "$authentication_output" | grep -Eq 'Authentications that can continue:.*publickey'; then printf '%s\n' password_auth=disabled
else printf '%s\n' password_auth=unknown; fi
