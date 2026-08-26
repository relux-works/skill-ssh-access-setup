#!/bin/sh
set -eu
public_key_file=${1:?public key file required}
ssh_dir=$HOME/.ssh
authorized_keys=$ssh_dir/authorized_keys
umask 077
mkdir -p "$ssh_dir"
touch "$authorized_keys"
public_key=$(cat "$public_key_file")
grep -Fqx "$public_key" "$authorized_keys" || printf '%s\n' "$public_key" >> "$authorized_keys"
chmod 700 "$ssh_dir"
chmod 600 "$authorized_keys"
rm -f "$public_key_file" "$HOME/authorize-unix.sh"
printf '%s\n' status=authorized authorized_keys="$authorized_keys"
