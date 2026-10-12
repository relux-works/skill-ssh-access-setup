#!/bin/sh
set -eu
target_os=${1:?target platform required}
case "$target_os" in macos|linux) ;; *) printf '%s\n' error_code=invalid_target_os >&2; exit 1 ;; esac
source_file=/tmp/key-only.conf
payload_file=/tmp/harden-unix.sh
destination_file=/etc/ssh/sshd_config.d/00-ssh-access-key-only.conf
backup_file=$destination_file.previous
sshd_binary=$(command -v sshd || true)
[ -n "$sshd_binary" ] || sshd_binary=/usr/sbin/sshd
[ -x "$sshd_binary" ] || { printf '%s\n' error_code=missing_sshd >&2; exit 1; }
mkdir -p /etc/ssh/sshd_config.d
[ ! -f "$destination_file" ] || cp -p "$destination_file" "$backup_file"
install -o root -g root -m 644 "$source_file" "$destination_file" 2>/dev/null || install -o root -g wheel -m 644 "$source_file" "$destination_file"
rollback() {
  if [ -f "$backup_file" ]; then mv "$backup_file" "$destination_file"; else rm -f "$destination_file"; fi
}
if ! "$sshd_binary" -t; then rollback; printf '%s\n' error_code=sshd_validation_failed >&2; exit 1; fi
effective_config=$("$sshd_binary" -T 2>/dev/null) || { rollback; printf '%s\n' error_code=sshd_effective_config_failed >&2; exit 1; }
if ! printf '%s\n' "$effective_config" | grep -Eq '^passwordauthentication no$' || ! printf '%s\n' "$effective_config" | grep -Eq '^authenticationmethods publickey$'; then
  rollback
  printf '%s\n' error_code=ineffective_sshd_dropin >&2
  exit 1
fi
if [ "$target_os" = linux ]; then
  if command -v systemctl >/dev/null 2>&1; then
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || { rollback; "$sshd_binary" -t; printf '%s\n' error_code=sshd_reload_failed >&2; exit 1; }
  elif command -v service >/dev/null 2>&1; then
    service sshd reload 2>/dev/null || service ssh reload 2>/dev/null || { rollback; "$sshd_binary" -t; printf '%s\n' error_code=sshd_reload_failed >&2; exit 1; }
  else
    rollback
    printf '%s\n' error_code=missing_service_manager >&2
    exit 1
  fi
fi
rm -f "$source_file" "$payload_file" "$backup_file"
printf '%s\n' status=hardened platform="$target_os" file="$destination_file"
