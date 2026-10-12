---
name: skill-ssh-access-setup
description: >
  Configure, verify, and optionally harden OpenSSH public-key access between macOS, Linux, or Windows machines over any available network route. Use for fresh-machine SSH bootstrap, direct LAN or public endpoints, VPN and overlay-network addresses, Tailscale, WireGuard, ZeroTier, bastions and ProxyJump, key installation, client aliases, Too many authentication failures, or disabling SSH password authentication; Russian triggers include "настроить SSH по ключу", "подключить новый компьютер по SSH", and "отключить вход по паролю SSH".
---

# SSH Access

## Default Mode

- Treat transport and SSH as separate layers. Use any user-authorized route that reaches the SSH endpoint; do not require or install a particular VPN or overlay product.
- Prefer an existing route. Tailscale, WireGuard, ZeroTier, other VPNs, LAN, routable addresses, tunnels, and bastions are adapters, not package identity.
- Execute managed commands and return outcomes. Show commands only at a human authentication, elevation, physical-access, or missing-runtime boundary.
- Support macOS, Linux, and Windows as client and target platforms. Resolve endpoint, port, optional ProxyJump, and both platforms before mutation.
- Answer entirely in the user's language. Preserve literal commands, paths, identifiers, status values, and URLs.

## Resolve Commands Once

Resolve `<ssh-access-discover>`, `<ssh-access-check>`, `<ssh-access-authorize>`, `<ssh-access-alias>`, and `<ssh-access-harden>` once:

- Search upward from the working directory and physical `SKILL.md` path for `.agents/bin/<command>`; on Windows use `<command>.cmd`.
- Otherwise use `global/bin` under the Curator home, then a bare command validated with `command -v` or `Get-Command`.
- In a source checkout without `.csk-install.json`, resolve the manifest's `unix_path` or `win_path` relative to the physical skill directory.
- Never execute a runtime path relative to the working directory or guess a Curator runtime-store path.

## Fast Path

1. Run `<ssh-access-discover>` once. Reuse an SSH config route or an optional detected adapter when appropriate; otherwise accept a user-supplied hostname/IP. Read `references/transports.md` only when route selection is ambiguous.
2. Select one public/private key pair and resolve target OS, account, endpoint, port (default `22`), and optional ProxyJump.
3. Run `<ssh-access-check> --host <endpoint> --port <port> --user <user> --key <private-key> [--proxy-jump <jump>] [--transport <label>]`.
4. If `ssh_port=closed`, read only the target section in `references/platforms.md` and stop at its physical-access or administrator boundary.
5. If `key_auth=missing`, preview `<ssh-access-authorize>` with the same route plus `--target-os` and `--public-key`. Give the exact `--apply` command to the user because initial password or elevation is human-only. Check once afterward.
6. Preview `<ssh-access-alias>` with the same route, then apply it when `status=would_add`. Refuse collisions.
7. Verify with `<ssh-access-check> --alias <alias>`.
8. When key-only hardening is requested, preview `<ssh-access-harden> --target-os <platform> --alias <alias>`, apply only after key authentication succeeds, keep an existing session open, then run `--verify`.

## Fresh Server Bootstrap

For a newly provisioned Linux server that must be locked down before any workload runs, read `references/server-bootstrap.md` after the Fast Path. It orders the optional scopes: key-only SSH with no password hashes, updates and a default-deny host firewall, overlay membership, overlay-only SSH, one-way reachability (owner devices reach the server, the server reaches none of them), and unprivileged service accounts. Run each scope only when the user authorized it, verify it from a fresh connection, and keep the provider's rescue console as the break-glass path.

## Safety

- Discovery and checks are read-only. Authorization, alias creation, and hardening preview by default and mutate only with `--apply`.
- Transfer only public keys and packaged payloads. Never read, print, upload, or persist private-key bytes or passphrases.
- Suppress unrelated identities during initial authorization. Never disable password authentication before a separate key-authenticated connection succeeds.
- Preserve existing client configuration. Write only one alias containing endpoint, port, account, key, and optional ProxyJump.
- On macOS/Linux, install one validated sshd drop-in; on Windows, back up and validate `%ProgramData%\ssh\sshd_config`. Confirm effective policy and roll back on validation or reload failure.
- Do not create public exposure, port forwarding, VPN membership, firewall rules, routes, or bastion accounts unless the user separately authorizes that scope.
- Never request a password in chat, arguments, logs, or environment variables.

## Output Contract

Return client/target platforms, transport label, endpoint, port, optional ProxyJump, remote account, key fingerprint/path, alias state, `ssh_port`, `key_auth`, `password_auth`, changed files, and remaining human actions. Do not omit failed, proxied, or unknown statuses.

## Pre-final Check

Confirm every requested outcome has a concrete status, no safe executable action remains, no secret entered output or logs, and no device-, organization-, session-, or transport-vendor-specific assumption entered core behavior.
