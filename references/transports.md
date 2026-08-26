# SSH transport adapters

Read this reference only when selecting or diagnosing the route to the SSH endpoint.

## Transport contract

The SSH workflow consumes four route values: endpoint, TCP port, optional `ProxyJump`, and a human-readable transport label. A transport is usable when it already provides TCP reachability to the target OpenSSH server. Transport setup and SSH setup are separate scopes.

Do not install a VPN, join a network, expose a public port, create firewall rules, add routes, provision a bastion account, or change DNS unless the user separately authorizes that work.

## Direct endpoint

- Use a resolvable hostname or IPv4/IPv6 address on an existing LAN, routed private network, or public network.
- Default to TCP port `22`; preserve a verified custom port.
- Public exposure is not implied by this skill. If no safe existing route reaches the host, stop at the network-administration boundary.

## VPN or overlay endpoint

- Use the address or DNS name already assigned by Tailscale, WireGuard, ZeroTier, another VPN, or an equivalent overlay.
- Tailscale may expose peer metadata through its CLI and is therefore an optional discovery adapter. Its presence is never required.
- Generic WireGuard and ZeroTier interfaces do not reliably identify which peer runs SSH; accept the endpoint from the user or existing network configuration.
- This package configures traditional OpenSSH. A vendor-specific SSH proxy or identity product is a different authentication path and must not be silently substituted.

## SSH config route

- Reuse an existing `Host` alias when `ssh -G <alias>` resolves its effective hostname, port, account, identity, and proxy settings.
- Treat wildcard `Host` patterns as configuration, not concrete endpoints.
- Do not overwrite or merge into an existing alias. Report a collision and let the user choose a different name or edit scope.

## Bastion or jump host

- Accept an existing OpenSSH jump specification such as `bastion`, `user@bastion`, or a comma-separated jump chain.
- Pass it as `ProxyJump`/`-J`; do not probe the target port directly from the client because the target may be reachable only from the jump host.
- The jump host must already be authorized and reachable. This skill does not install keys on or otherwise configure the bastion unless the user explicitly includes it as another SSH target.

## Primary references

- OpenSSH client configuration, including `Port` and `ProxyJump`: <https://man.openbsd.org/ssh_config>
- Tailscale connectivity as an optional example of traditional SSH over an overlay: <https://tailscale.com/kb/1452/connect-to-devices>
