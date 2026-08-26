# skill-ssh-access-setup

Reusable agent skill for OpenSSH public-key access over any existing network route. It supports direct LAN/public endpoints, VPN or overlay addresses, SSH config aliases, custom ports, and bastions through `ProxyJump`, with macOS, Linux, and Windows as clients and targets.

The package configures the SSH layer; it does not require, install, or mutate a transport. Tailscale is one optional discovery adapter alongside generic user-supplied endpoints and existing SSH config routes.

## Layout

- `SKILL.md` — agent workflow and safety contract.
- `agent-skill.json` — Curator commands, runtime roots, capabilities, and dependencies.
- `scripts/unix/` and `scripts/windows/` — client-platform entrypoints.
- `payloads/` — target-platform authorization and hardening payloads.
- `references/platforms.md` — platform-specific bootstrap and recovery details.
- `references/transports.md` — route selection, custom ports, overlays, and bastions.
- `locales/` and `.skill_triggers/` — English/Russian activation metadata.

## Validate

```bash
curator skill check . --locale en
curator skill check . --locale ru
csk skill check . --json
sh -n scripts/unix/*.sh payloads/*.sh
```

Treat warnings as failures. Run PowerShell parser checks plus direct, proxied, and optional-adapter mock tests before publishing a release.

## Install through Curator

Publish the reviewed source as a Git commit and immutable tag, then use:

```bash
curator add skill-ssh-access-setup --project /path/to/project --git https://github.com/relux-works/skill-ssh-access-setup.git --tag <release-tag>
curator status /path/to/project --check
```

For machine-wide use:

```bash
curator global add skill-ssh-access-setup --git https://github.com/relux-works/skill-ssh-access-setup.git --tag <release-tag>
curator global status --check
```

A development `Skillfile.dev.json` path substitution is allowed, but the source checkout must still have a valid Git `HEAD` because Curator installs a commit snapshot.

## Tools and outputs

- `curator` validates and installs prompt context under `.agents/skills/`, runtime content in its protected store, and command shims under `.agents/bin/`.
- `csk` independently validates the package protocol.
- `ssh-access-discover` emits deterministic TSV discovery data without requiring a VPN client.
- Other exported commands emit schema-versioned `key=value` status.
- Preview is the default; authorization, alias creation, and hardening require explicit `--apply`.
