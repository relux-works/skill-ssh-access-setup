#!/bin/sh
set -eu

fail() { printf '%s\n' "error_code=$1" "action=$2" >&2; exit 1; }
ssh_alias= target_os= apply=false verify_only=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --alias) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --alias."; ssh_alias=$2; shift 2 ;;
    --target-os) [ "$#" -ge 2 ] || fail invalid_arguments "Provide a value after --target-os."; target_os=$2; shift 2 ;;
    --apply) apply=true; shift ;;
    --verify) verify_only=true; shift ;;
    *) fail invalid_arguments "Use --target-os PLATFORM --alias NAME [--apply | --verify]." ;;
  esac
done
case "$target_os" in macos|linux|windows) ;; *) fail invalid_target_os "Use macos, linux, or windows." ;; esac
[ -n "$ssh_alias" ] || fail invalid_arguments "Provide --alias NAME."
[ "$apply" = false ] || [ "$verify_only" = false ] || fail invalid_arguments "Choose either --apply or --verify."

verify() {
  if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$ssh_alias" 'exit 0' >/dev/null 2>&1; then
    printf '%s\n' schema_version=1 "alias=$ssh_alias" key_auth=failed password_auth=not_checked
    return 1
  fi
  authentication_output=$(ssh -vv -o BatchMode=yes -o ConnectTimeout=10 -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive "$ssh_alias" 'exit 0' 2>&1 || true)
  printf '%s\n' schema_version=1 "alias=$ssh_alias" key_auth=ok
  if printf '%s\n' "$authentication_output" | grep -Eq 'Authentications that can continue:.*(password|keyboard-interactive)'; then printf '%s\n' password_auth=enabled; return 1; fi
  if printf '%s\n' "$authentication_output" | grep -Eq 'Authentications that can continue:.*publickey'; then printf '%s\n' password_auth=disabled; return 0; fi
  printf '%s\n' password_auth=unknown
  return 1
}

if [ "$verify_only" = true ]; then verify; exit $?; fi
remote_file=/etc/ssh/sshd_config.d/00-ssh-access-key-only.conf
[ "$target_os" = windows ] && remote_file='%ProgramData%\ssh\sshd_config'
printf '%s\n' schema_version=1 "action=$([ "$apply" = true ] && printf apply || printf preview)" "status=$([ "$apply" = true ] && printf applying || printf would_harden)" "target_os=$target_os" "alias=$ssh_alias" "remote_file=$remote_file" requires=administrator_privileges
[ "$apply" = true ] || exit 0
ssh -o BatchMode=yes -o ConnectTimeout=10 "$ssh_alias" 'exit 0' >/dev/null 2>&1 || fail key_auth_required "Install and verify the public key before hardening SSH."

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
payload_root=$(CDPATH= cd -- "$script_dir/../../payloads" && pwd)
if [ "$target_os" = windows ]; then
  scp -o BatchMode=yes "$payload_root/harden-windows.ps1" "$ssh_alias:" >/dev/null || fail payload_transfer_failed "Verify SCP support and the remote home directory."
  if ! ssh -o BatchMode=yes "$ssh_alias" 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\harden-windows.ps1'; then
    fail administrator_auth_required "Run the staged PowerShell payload from an elevated retained session."
  fi
else
  scp -o BatchMode=yes "$payload_root/key-only.conf" "$payload_root/harden-unix.sh" "$ssh_alias:/tmp/" >/dev/null || fail payload_transfer_failed "Verify SCP access to /tmp."
  if ! ssh -o BatchMode=yes "$ssh_alias" "sudo -n /bin/sh /tmp/harden-unix.sh '$target_os'"; then
    fail administrator_auth_required "Run interactively: ssh -t $ssh_alias \"sudo /bin/sh /tmp/harden-unix.sh '$target_os'\""
  fi
fi
verify
