# Fresh server bootstrap

Read this reference only for a newly provisioned Linux server (a rented dedicated or cloud machine) whose owner wants it locked down before any workload runs on it. Every step after key access is a separate scope: run it only when the user authorized that scope, verify it, and report its status.

## 0. Provisioning (human boundary)

- Pre-install the client's public key in the provider's install form (for example an `SSH Public Key` field). Leave post-install scripts and cloud-init metadata empty unless the user supplies them.
- Note the provider's default account (often `ubuntu`, `debian`, or `admin`); providers commonly refuse `root` with a "login as the user …" message.
- Record the break-glass path before closing anything: the provider's rescue mode, KVM, or serial console.
- Disk layout is the user's decision. A software RAID0 root trades redundancy for capacity; keep `/boot` on RAID1 and leave room for swap on each member disk.

## 1. Key access

Run the normal Fast Path (`check`, `alias`) against the public endpoint. Accept the new host key with `StrictHostKeyChecking=accept-new` only on the first connection to a freshly installed host, then keep it pinned.

## 2. Key-only SSH ("password login blocked for good")

- Apply `<ssh-access-harden> --target-os linux --alias <alias> --apply`. The packaged drop-in sets `AuthenticationMethods publickey`, `PermitEmptyPasswords no`, and disables password and keyboard-interactive authentication.
- Add `PermitRootLogin no` (or `prohibit-password` when root must stay reachable by key) only when the user asks for it. Put it in the same drop-in; the first value read wins, so a lexically early file such as `00-…` beats distribution files such as `50-cloud-init.conf` or `60-cloudimg-settings.conf`.
- Confirm that no account holds a usable password hash: every relevant `/etc/shadow` entry starts with `!` or `*`. Lock a remaining one with `passwd -l <user>` only after confirming its owner signs in by key.
- Verify from a separate connection: `<ssh-access-harden> --verify` must report `password_auth=disabled`, and a forced password attempt must fail with `Permission denied (publickey)`.

## 3. Updates and host firewall (separate scope)

- Apply pending updates (`apt-get full-upgrade` with a non-interactive frontend) and check `/var/run/reboot-required`.
- Default-deny inbound, allow outbound, then allow only the SSH port and the overlay's transport port (for example `ufw default deny incoming`, `ufw allow 22/tcp`, `ufw allow 41641/udp` for Tailscale's direct path).
- Optionally add an SSH brute-force filter such as `fail2ban` with an `sshd` jail (`backend = systemd`). It reduces log noise and load; it is not the access control.

## 4. Overlay membership (separate scope)

- Install the overlay client from its vendor's documented installer and join with an interactive login URL the user approves. Never paste an auth key into chat, argv, or logs.
- Add an SSH config alias for the overlay address and verify key login over it before changing public exposure.
- Unattended servers should not fall off the overlay when a node key expires: disable key expiry for that device (in Tailscale a tagged device or "Disable key expiry"; other overlays have equivalents).

## 5. Overlay-only SSH (separate scope)

Only after step 4 verified a fresh overlay login:

1. Allow SSH on the overlay interface (`ufw allow in on <overlay-if> to any port 22 proto tcp`).
2. Remove the public rule (`ufw delete allow 22/tcp`).
3. Verify a fresh overlay login succeeds and the public `host:22` is closed from outside.

Keep the overlay's transport port open; it is not SSH.

## 6. One-way reachability (separate scope)

When the owner wants their devices to reach the server but not the reverse, enforce it in two layers:

- **Overlay policy (authoritative).** Give the server a role identity that no rule uses as a source. Tailscale example: tag the server `tag:server`, replace the default `{"src": ["*"], "dst": ["*"], "ip": ["*"]}` with `{"src": ["autogroup:member"], "dst": ["*"], "ip": ["*"]}`, and grant other tagged machines that must reach the server explicitly (for example `{"src": ["tag:<ops-host>"], "dst": ["tag:server"], "ip": ["*"]}`). Tagged devices are not `autogroup:member`, so list existing tags before switching the source, or they lose access.
- **Host egress filter (defense in depth).** Deny new outbound connections into the overlay range while replies to inbound sessions still pass via connection tracking. Tailscale example: `ufw allow out on tailscale0 to 100.100.100.100 port 53` (MagicDNS), `ufw deny out on tailscale0 to 100.64.0.0/10`, `ufw deny out on tailscale0 to fd7a:115c:a1e0::/48`.

Verify both directions: an owner device or ops host reaches the server; from the server, a connection to a peer's SSH port returns no banner. Test through the overlay daemon as well (for example `tailscale nc <peer> 22`), because it bypasses the host firewall and proves the policy layer alone.

## 7. Service accounts

- Run workloads (CI runners, agents) under a dedicated account without sudo, a password, or membership in privileged groups such as `docker` unless the user accepts that root-equivalent grant.
- Pass enrollment tokens through a pipe from the issuing CLI straight into the consumer, for example via an `ACTIONS_RUNNER_INPUT_TOKEN`-style environment variable read from stdin. Never print them, put them in argv, or write them to files.
- Register self-hosted CI runners only for private repositories unless the user explicitly accepts running fork code from public ones.

## Output

Report per step: the applied change, the file or rule, the verification evidence, and the break-glass path that remains.
