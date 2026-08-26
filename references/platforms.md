# Platform-specific OpenSSH operations

Read only the section for the resolved target platform.

## macOS target

- Enable **System Settings → General → Sharing → Remote Login** and allow the intended account. This is a physical-access or existing-management boundary.
- Store per-user keys in `~/.ssh/authorized_keys` with directory mode `700` and file mode `600`.
- Validate server changes with `/usr/sbin/sshd -t`.
- Use `/etc/ssh/sshd_config.d/00-ssh-access-key-only.conf`; new Apple-launched sshd sessions read the validated configuration without a Linux service reload.
- Recover locally by removing that drop-in and rerunning `/usr/sbin/sshd -t`.

## Linux target

- Install and enable the distribution's OpenSSH server package through machine bootstrap. Common services are `sshd` and `ssh`; do not guess a package manager without detecting the distribution.
- Store per-user keys in `~/.ssh/authorized_keys` with directory mode `700` and file mode `600`.
- Validate syntax with the resolved `sshd -t` binary and confirm the installed policy appears in `sshd -T`; fail and roll back when the distribution does not include the drop-in directory.
- Install `/etc/ssh/sshd_config.d/00-ssh-access-key-only.conf`, then reload `sshd` or `ssh`. Roll back if validation or reload fails.
- Recover from a console or retained session by removing the drop-in, validating, and reloading the detected service.

## Windows target

- Install OpenSSH Server as a Windows capability, start `sshd`, set it to automatic startup, and verify the `OpenSSH-Server-In-TCP` firewall rule from an elevated PowerShell session.
- A standard user uses `%USERPROFILE%\.ssh\authorized_keys`. A member of the built-in Administrators group uses `%ProgramData%\ssh\administrators_authorized_keys` under the default Microsoft configuration.
- Restrict `administrators_authorized_keys` ACLs to `SYSTEM` and `BUILTIN\Administrators`.
- The server reads `%ProgramData%\ssh\sshd_config` at service start. Back it up, prepend the managed authentication block, validate with `sshd.exe -t -f`, and restart `sshd`.
- Windows OpenSSH supports `password` and `publickey`; do not add unsupported `KbdInteractiveAuthentication` directives.
- Recover from an elevated console or retained session by restoring the `.ssh-access.previous` backup and restarting `sshd`.

## Client notes

- macOS, Linux, and Windows OpenSSH clients all read the SSH config under the user's `.ssh` directory.
- Keep aliases portable: use `HostName`, `Port`, `User`, `IdentityFile`, `IdentitiesOnly`, and optional `ProxyJump`.
- On macOS, load encrypted keys into Keychain only when requested with `ssh-add --apple-use-keychain <key>`.
- On Linux, use the user's selected SSH agent or enter the key passphrase interactively.
- On Windows, use `ssh-add` with the Windows OpenSSH Authentication Agent only when that service is intentionally enabled.

## Primary references

- Windows OpenSSH Server installation: <https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse>
- Windows OpenSSH Server configuration: <https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration>
- Windows OpenSSH key management: <https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement>
- Portable `sshd_config` directives: <https://man.openbsd.org/sshd_config>
