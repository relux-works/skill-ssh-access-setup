#!/bin/sh
set -eu

fail() { printf '%s\n' "error_code=$1" "action=$2" >&2; exit 1; }
[ "$#" -eq 0 ] || fail invalid_arguments "Run ssh-access-discover without arguments."
for command_name in ssh-keygen awk sort; do
  command -v "$command_name" >/dev/null 2>&1 || fail missing_dependency "Install or enable '$command_name' through machine bootstrap."
done

export LC_ALL=C
printf 'record\ttransport\tendpoint\tname\towner\tos\tstate\tpath\tdetails\n'
printf 'adapter\tdirect\t-\t-\t-\t-\tavailable\t-\tuser_supplied_endpoint\n'

ssh_config=$HOME/.ssh/config
if [ -f "$ssh_config" ]; then
  printf 'adapter\tssh-config\t-\t-\t-\t-\tavailable\t%s\texisting_aliases\n' "$ssh_config"
  awk '
    tolower($1) == "host" {
      for (i=2; i<=NF; i++) {
        if ($i !~ /[*?!\[\]]/) printf "route\tssh-config\t%s\t%s\t-\t-\tconfigured\t-\talias\n", $i, $i
      }
    }
  ' "$ssh_config" | sort -t '	' -k3,3
else
  printf 'adapter\tssh-config\t-\t-\t-\t-\tunconfigured\t%s\tno_config\n' "$ssh_config"
fi

if command -v tailscale >/dev/null 2>&1; then
  if status_output=$(tailscale status 2>/dev/null); then
    printf 'adapter\ttailscale\t-\t-\t-\t-\tavailable\t-\tpeer_discovery\n'
    printf '%s\n' "$status_output" | awk '
      tolower($4) == "linux" || tolower($4) == "macos" || tolower($4) == "windows" {
        state = "available"
        if ($0 ~ /offline/) state = "offline"
        else if ($0 ~ /idle/) state = "idle"
        else if ($0 ~ /active/) state = "active"
        printf "route\ttailscale\t%s\t%s\t%s\t%s\t%s\t-\tpeer\n", $1, $2, $3, $4, state
      }
    ' | sort -t '	' -k4,4
  else
    printf 'adapter\ttailscale\t-\t-\t-\t-\tunavailable\t-\tnot_authenticated\n'
  fi
fi
if command -v zerotier-cli >/dev/null 2>&1; then printf 'adapter\tzerotier\t-\t-\t-\t-\tavailable\t-\tmanual_endpoint_required\n'; fi
if command -v wg >/dev/null 2>&1; then printf 'adapter\twireguard\t-\t-\t-\t-\tavailable\t-\tmanual_endpoint_required\n'; fi

for public_key in "$HOME"/.ssh/*.pub; do
  [ -f "$public_key" ] || continue
  fingerprint=$(ssh-keygen -lf "$public_key") || fail invalid_public_key "Inspect or replace the public key at $public_key."
  printf 'key\tlocal\t-\t-\t-\t-\tavailable\t%s\t%s\n' "$public_key" "$fingerprint"
done
