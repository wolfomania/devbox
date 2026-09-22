# Matrix OS gaps

Box-setup features in [Matrix OS](https://github.com/hamedmp/matrix-os)
(commit `feadc2d`, 2026-09-23) that devbox lacks. UI, gateway and platform
code are out of scope. Paths are relative to the Matrix OS repository.

## Supply chain

- Release downloads are checked against a pinned SHA-256 before extraction.
  devbox `release` modules check nothing. Evidence: `Dockerfile.dev:108-127`
  (gh, Zellij).
- Release versions are pinned per tool (`ARG *_VERSION`). devbox `release`
  modules install the newest GitHub release (`lib/pkg.sh:164`).
- The host bundle is checked against a published `.sha256` file before
  install. Evidence: `scripts/install-server.sh:479-510`.
- Shell plugins are cloned at pinned tags. Evidence: `Dockerfile.dev:142-148`.

## Agent sandboxing

- `bubblewrap` is installed for the Codex per-command sandbox. Evidence:
  `Dockerfile.dev:29`, `scripts/install-server.sh:380`.
- An AppArmor profile at `/etc/apparmor.d/bwrap` grants `userns` to
  `/usr/bin/bwrap`, then AppArmor is reloaded. Ubuntu 24.04+ blocks
  unprivileged user namespaces without it. Evidence:
  `scripts/install-server.sh:350-370`,
  `distro/customer-vps/cloud-init.yaml:546-556`.
- `socat` is installed for sandboxed network proxying. Evidence:
  `scripts/install-server.sh:380`.
- Agents run as a non-root user; the Agent SDK refuses
  `bypassPermissions` as root. Evidence: `Dockerfile.dev:130-131`.
- Short-lived agent jobs run under a fixed systemd profile: `DynamicUser`,
  `PrivateUsers`, `PrivateNetwork`, `ProtectHome`, `ProtectSystem=strict`,
  `ProtectProc=invisible`, `MemoryMax`, `TasksMax`, `RuntimeMaxSec=90`.
  Evidence: `specs/124-organization-collaboration/research.md`.

## Host hardening

- Secret env files are written mode `0600`. Evidence:
  `scripts/install-server.sh:602-610`.
- Services carry `MemoryHigh`/`MemoryMax`, restart policies and start
  timeouts. Evidence: `distro/customer-vps/cloud-init.yaml:98-99,143,167`.
- `vm.swappiness=10` is set with the swapfile. devbox `swap` sets no
  swappiness. Evidence: `distro/customer-vps/cloud-init.yaml:487`.
- Install steps run under `timeout` with bounded `curl` retries. Evidence:
  `distro/customer-vps/cloud-init.yaml:542-560`.
- Ingress runs through a Cloudflare tunnel, not open ports. Evidence:
  `distro/cloudflared.yml`, `distro/cloudflared-dev-vps.yml`.
- Logs ship to Loki through Grafana Alloy. Evidence:
  `scripts/enable-vps-logship.sh`,
  `distro/customer-vps/host-bin/matrix-install-logship`.

Matrix OS has no SSH hardening, firewall, fail2ban or unattended-upgrades.
`scripts/install-server.sh:783` defers ingress to "HTTPS, Tailscale,
Cloudflare Access, or another trusted edge".

## Tools

| Tool | Purpose | Evidence |
|---|---|---|
| Zellij | terminal multiplexer | `Dockerfile.dev:120-127` |
| code-server | VS Code in a browser | `Dockerfile.dev:95-101` |
| opencode | coding agent CLI | `Dockerfile.dev:79` |
| pi-coding-agent | coding agent CLI, `--ignore-scripts` | `Dockerfile.dev:80-81` |
| Hermes agent | coding agent, pinned tag | `Dockerfile.dev:83-90` |
| QMD | BM25 and vector search over files, MCP server | `Dockerfile.dev:104` |
| zsh, Powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting | shell | `Dockerfile.dev:142-153` |
| strace, lsof, rsync, bind-tools, netcat, zip | debugging baseline | `Dockerfile.dev:24-67` |

## Shell defaults

- `distro/zshrc`: shared history (5000 lines, `hist_ignore_dups`,
  `hist_ignore_space`), aliases `ll`, `la`, `gs`, `gd`, `gl`, and
  `~/.local/bin` on `PATH`.

## Candidate modules

Ordered by value to devbox:

1. Verify SHA-256 and pin versions in every `release` module.
2. `sandbox`: install `bubblewrap` and `socat`, write the AppArmor `bwrap`
   profile on Ubuntu 24.04+.
3. `swap`: set `vm.swappiness=10`.
4. `zellij`, `opencode` as optional modules.
5. `zsh` with pinned Powerlevel10k and plugins.
6. `debug` part set: strace, lsof, rsync, dnsutils, netcat-openbsd, zip.
