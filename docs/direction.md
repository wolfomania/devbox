# devbox direction and roadmap, 2026-09 to 2027-03

As of 2026-09-23. Window: 2026-09-23 to 2027-03-23, in months M1–M6.

## Purpose

Record devbox's product direction, the components for each feature in scope, and the 6-month roadmap.

The chosen direction is D4 for M1–M4, then branch A or branch B for M5–M6.

## Chosen direction

### Definition

- M1–M4 build D4, the hardened governed base box ([Directions considered](#directions-considered)).
- D4 keeps the existing `firewall`, `updates` and `swap` modules and the `exclave` account. `DVB_ACCOUNT` overrides the account name. (`README.md:13-19`)
- On 2027-01-23, the end of M4, record branch A or branch B.
- Branch A needs, on 2027-01-23, every M1–M3 exit criterion passing and at least 3 teams holding a signed pilot agreement for the team layer.
- Otherwise, branch B applies.
- If any M4 exit criterion still fails on 2027-02-20, branch B replaces branch A.
- Branch A adds a team layer: a central read-only view of audit and spend across boxes and gateways, and the Owner, Member and Auditor policy roles.
- Branch B adds the Matrix OS module, the EU routing gateway profile and Debian coverage.
- Scope: the deliverables in the [6-month roadmap](#6-month-roadmap).

### Target user

- Developers and small teams who run Claude Code, Codex or OpenCode on a Debian or Ubuntu box they control.
- Branch A: teams that run agents from more than one vendor on Debian or Ubuntu boxes they manage, or that need OS-level controls that client-side agent settings do not give.
- Branch B: developers who self-host Matrix OS on a Debian or Ubuntu box.

### Non-goals in the window

- Any hosted or managed service.
- A web console that changes permissions.
- Fine-grained human roles, custom roles, SAML, SCIM and multi-org.
- Controls that bind an account which keeps root, sudo or `docker` group membership.
- Capping Claude Team, Claude Enterprise or any subscription OAuth traffic.
- Distros beyond Debian and Ubuntu.
- OpenClaw and Hermes Agent modules.
- Offering or brokering claude.ai or ChatGPT logins.
- Matrix OS application-layer controls.
- Writing an LLM gateway.

## Features in scope mapped to components

- "devbox" in the Licence column means devbox's own code, existing or new, under the licence that M1 adds.
- "Proprietary (Anthropic)" means use is subject to Anthropic's legal agreements. (<https://github.com/anthropics/claude-code/blob/main/LICENSE.md>, <https://code.claude.com/docs/en/legal-and-compliance>)

### Roles and permissions

| Component | Licence | Reuse or build | Source |
|---|---|---|---|
| `agent` account: no sudo, outside the `docker` group, with the agent CLIs installed for it | devbox | Build | `lib/account.sh`, `modules/optional/docker.sh`, <https://docs.docker.com/engine/install/linux-postinstall/> |
| Account mode `governed`: human accounts without `NOPASSWD:ALL`; a separate break-glass account whose sudo use is logged | devbox | Build | `lib/account.sh` |
| Permission levels `locked`, `standard` and `open`; see [Permission levels](#permission-levels) | devbox | Build | — |
| Policy roles, branch A: Owner signs policy, Member uses boxes without root, Auditor reads the central view | devbox | Build | — |
| bubblewrap, per process | LGPL-2.0-or-later | Reuse | <https://github.com/containers/bubblewrap/blob/main/bubblewrap.c> |
| `srt` | Apache-2.0 | Reuse | <https://github.com/anthropics/sandbox-runtime> |
| Codex sandbox | Apache-2.0 | Reuse | <https://github.com/openai/codex> |
| Claude Code sandbox and endpoint-managed settings | Proprietary (Anthropic) | Reuse | <https://code.claude.com/docs/en/managed-settings> |
| Rootless Docker or Podman for `agent` | Apache-2.0 | Reuse | <https://github.com/moby/moby>, <https://github.com/containers/podman> |
| Tailscale SSH and ACLs | BSD-3-Clause client | Reuse | <https://github.com/tailscale/tailscale>, <https://tailscale.com/docs/features/tailscale-ssh> |

- `lib/account.sh` grants the provisioned account `NOPASSWD:ALL` today.
- `modules/optional/docker.sh` adds the provisioned account to the `docker` group today.
- Docker: "The `docker` group grants root-level privileges to the user." (<https://docs.docker.com/engine/install/linux-postinstall/>)
- Humans exchange code with the agent through a git remote.
- Git refuses to work in a repository another user owns unless it is listed in `safe.directory`. (<https://git-scm.com/docs/git-config>)

#### Permission levels

| Level | Internet default | Agent sandbox | Allowlist |
|---|---|---|---|
| `locked` | Off | On | None |
| `standard` | On | On | GitHub and package-registry presets |
| `open` | On | Off | Every host |

- The internet toggle overrides a level's internet default.
- The [`egress` module rules](#egress-module-rules) apply at every level.

### UI to change a box's permissions

| Component | Licence | Reuse or build | Source |
|---|---|---|---|
| Existing curses TUI, `--profile` and `--save-profile` | devbox | Reuse | `tui/`, `README.md` |
| TUI permission screen: permission level, internet toggle, allowlist, remaining budget, recent events split by person and agent | devbox | Build | — |
| `devbox policy` CLI with the same controls | devbox | Build | — |
| Policy applier: Python stdlib script in a root-owned systemd unit | devbox | Build | — |
| Signature check: `ssh-keygen -Y verify` or `git verify-commit` against a root-owned allowed-signers file | OpenSSH: BSD or more permissive; Git: GPL-2.0 | Reuse | <https://github.com/openssh/openssh-portable/blob/master/LICENCE>, <https://github.com/git/git/blob/master/COPYING> |
| Policy source: a git repository of signed policy files that boxes pull | devbox | Build | — |
| Central read-only view of box state, audit and spend, branch A | devbox | Build | — |

- The Python stdlib cryptography modules are `hashlib`, `hmac` and `secrets` only. (<https://docs.python.org/3/library/crypto.html>)

### Internet on/off per box

| Component | Licence | Reuse or build | Source |
|---|---|---|---|
| nftables table matching the agent UID (`meta skuid`) | GPL-2.0 | Reuse | <https://wiki.nftables.org/wiki-nftables/index.php/Configuring_chains>, <https://metadata.ftp-master.debian.org/changelogs/main/n/nftables/unstable_copyright> |
| Agent resolver: dnsmasq answers only allowlisted names; `--nftset` feeds an nftables set | GPL-2.0 or GPL-3.0 | Reuse | <https://manpages.debian.org/testing/dnsmasq-base/dnsmasq.8.en.html>, <https://thekelleys.org.uk/dnsmasq/doc.html> |
| Forward proxy under its own UID: smokescreen or Squid | MIT; GPL-2.0 | Reuse | <https://github.com/stripe/smokescreen>, <https://github.com/squid-cache/squid> |
| Per-process allowlist: `srt` or `coder/boundary` | Apache-2.0; MIT | Reuse | <https://github.com/anthropics/sandbox-runtime>, <https://github.com/coder/boundary> |
| `egress` module | devbox | Build | — |

#### `egress` module rules

- Model host: the gateway under the `claude-gateway` and `litellm` gateway profiles; Anthropic under `claude-team`.
- The agent UID reaches the model host with internet on or off.
- Under `claude-gateway` and `litellm`, the agent UID reaches no other model provider.
- Internet off drops every other new output from the agent UID.
- Internet on also allows the agent UID the allowlist.
- Box-wide mode is a per-box switch that applies internet off to human UIDs too.
- Exempt named system UIDs for updates, time sync, the audit shipper and the policy pull.
- Deny the agent port 53 except to the agent resolver.
- Allow replies to inbound SSH through connection state.
- Give Tailscale no blanket exemption.
- Add a `DOCKER-USER` rule and run the agent's containers rootless.
- Ship allowlist presets for GitHub and package registries.

Current state and limits:
- `modules/system/firewall.sh` sets `ufw default allow outgoing`.
- ufw has no hostname field. (<https://manpages.debian.org/trixie/ufw/ufw.8.en.html>)
- Docker traffic bypasses ufw rules. (<https://docs.docker.com/engine/network/packet-filtering-firewalls/>)
- CDN IP rotation breaks IP allowlists. (<https://github.com/openconveyor/openconveyor/issues/25>)

### AI API budget

| Component | Licence | Reuse or build | Source |
|---|---|---|---|
| Claude apps gateway, `enforcement.fail_closed_on_error: true` | Proprietary (Anthropic) | Reuse | <https://code.claude.com/docs/en/claude-apps-gateway-spend-limits> |
| LiteLLM proxy with Postgres, `fail_closed_budget_enforcement: true` | MIT core | Reuse | <https://docs.litellm.ai/docs/proxy/users> |
| Cloudflare AI Gateway spend limits | Hosted service | Reuse | <https://developers.cloudflare.com/ai-gateway/features/spend-limits/> |
| Gateway profile `claude-gateway`: Claude Code signs in to the team's apps gateway; the gateway delivers managed settings by IdP group and must set `managedSourcesBehavior: "merge"` or carry the hooks and OpenTelemetry settings | devbox | Build | <https://code.claude.com/docs/en/server-managed-settings>, <https://code.claude.com/docs/en/managed-settings> |
| Gateway profile `claude-team`: Claude Team or Enterprise subscribers, no base-URL override | devbox | Build | <https://code.claude.com/docs/en/server-managed-settings> |
| Gateway profile `litellm`: Codex custom provider, OpenCode provider config, Claude Code without an IdP | devbox | Build | <https://learn.chatgpt.com/docs/config-file/config-reference> |
| EU routing gateway profile: gateway to Bedrock or Google Cloud in an EU region; cloud credentials stay on the gateway | devbox | Build | <https://code.claude.com/docs/en/claude-apps-gateway> |

- The apps gateway's budgets fail open unless `enforcement.fail_closed_on_error` is `true`. (<https://code.claude.com/docs/en/claude-apps-gateway-spend-limits>)
- LiteLLM's `fail_closed_budget_enforcement` defaults to off. (<https://docs.litellm.ai/docs/proxy/users>)
- LiteLLM budgets cap nothing on a deployment without a database. (<https://docs.litellm.ai/docs/proxy/users>)
- With `fail_closed_budget_enforcement: true`, LiteLLM returns 503 only when neither Redis nor the database can verify spend. (<https://docs.litellm.ai/docs/proxy/users>)
- LiteLLM caches database spend reads in-process for a few seconds. (<https://docs.litellm.ai/docs/proxy/users>)
- Fail-closed enforcement is a gateway setting, not a box setting.
- LiteLLM and Portkey document only API-key authentication to Anthropic. (<https://docs.litellm.ai/docs/providers/anthropic>, <https://portkey.ai/docs/integrations/llms/anthropic>)
- A non-default `ANTHROPIC_BASE_URL` makes Claude Code skip the claude.ai managed-settings fetch. (<https://code.claude.com/docs/en/server-managed-settings>)
- Apps-gateway sessions have no server-side web search and no Remote Control. (<https://code.claude.com/docs/en/claude-apps-gateway>)
- Anthropic's first-party API accepts `inference_geo` values `us` and `global` only. (<https://platform.claude.com/docs/en/manage-claude/data-residency>)

### Traceability of agent and person

| Component | Licence | Reuse or build | Source |
|---|---|---|---|
| auditd: agent rules on `uid`/`euid`; person rules on `auid` with `euid` other than the agent; `-e 2` lock | GPL-2.0; libaudit LGPL-2.1 | Reuse | <https://github.com/linux-audit/audit-userspace>, <https://man7.org/linux/man-pages/man8/auditctl.8.html> |
| Vector `aws_s3` sink, batch timeout below the 300 s default | MPL-2.0 | Reuse | <https://github.com/vectordotdev/vector>, <https://vector.dev/docs/reference/configuration/sinks/aws_s3/> |
| S3 Object Lock in compliance mode, with write-only box credentials | AWS service | Reuse | <https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html> |
| Claude Code hooks and OpenTelemetry, pinned in endpoint-managed settings with `allowManagedHooksOnly` | Proprietary (Anthropic) | Reuse | <https://code.claude.com/docs/en/hooks>, <https://code.claude.com/docs/en/monitoring-usage> |
| Codex hooks and OpenTelemetry | Apache-2.0 | Reuse | <https://learn.chatgpt.com/docs/hooks> |
| Tailscale configuration audit log | Hosted service | Reuse | <https://tailscale.com/docs/features/logging/audit-logging> |
| Matrix OS kernel `audit.jsonl` | AGPL-3.0 | Reuse | <https://github.com/HamedMP/matrix-os/blob/5f6d0ce711bf83d24c766b1572c25fd450efe799/packages/kernel/src/audit.ts> |
| `audit` module: rules, shipper, prompt content off by default, one fixed retention period | devbox | Build | — |

- `auid` is "the original ID the user logged in with" and survives sudo. (<https://man7.org/linux/man-pages/man8/auditctl.8.html>)
- An agent started with `sudo -u agent` logs the person as `auid` and the agent as `euid`.
- `-e 2` blocks audit rule changes until reboot. (<https://man7.org/linux/man-pages/man8/auditctl.8.html>)
- Codex docs call hooks "a useful guardrail, not a complete enforcement boundary". (<https://learn.chatgpt.com/docs/hooks>)
- Keys in `/etc/claude-code/managed-settings.json` that apply under a claude.ai or Claude apps gateway policy: [Managed settings precedence](backlog.md#managed-settings-precedence).
- auditd attribution applies under every Claude Code policy source.

## 6-month roadmap

Rules:
- Each month ends with a tagged release and a green `tests/modules/run.sh`.
- Any failed negative test blocks a release.
- Module list, order and evidence: [backlog.md](backlog.md).

### M1, to 2026-10-23

Deliverables:
- LICENSE and SECURITY.md.
- Pinned version and SHA-256 check for the 9 modules with `channel = "release"` in `manifests/`.
- `claude-code` install without `curl | bash`.
- `agent` account and agent tooling, choosing between a second install via `DVB_ACCOUNT` and system-wide paths.
- Account mode `governed`.
- `sandbox` module.
- Owner decision on the product name (collision with [`jetify-com/devbox`](https://github.com/jetify-com/devbox)).

Exit criteria:
- A tampered checksum makes `install` fail.
- As `agent`, `sudo -n true` and `docker info` fail.
- As `agent`, `claude --version` and `codex --version` succeed.
- As a human in `governed`, `sudo -n true` fails.
- `bwrap --unshare-net true` succeeds as `agent` on Ubuntu 24.04.

### M2, to 2026-11-23

Deliverables:
- `egress` module and agent resolver.
- Rootless containers for `agent`.
- `sshd` module: key-only login, no root login.
- `tailscale` and `opencode` modules.
- Negative tests added to `tests/vps/assert.sh`.

Exit criteria, on an EC2 scenario:
- With internet off, the agent reaches no host other than the model host, by IP or by name.
- A DNS-tunnel probe fails.
- The agent reaches no tailnet peer or exit node.
- With internet off, the agent's containers reach no host other than the model host.
- The SSH or Tailscale session survives.
- `unattended-upgrades` completes.
- With internet on, the agent reaches only the model host and allowlisted hosts.
- `opencode` passes `tests/module-case.sh`.

### M3, to 2026-12-23

Deliverables:
- Gateway profiles `claude-gateway`, `claude-team` and `litellm`.
- Reference apps gateway and LiteLLM on a separate VM with Postgres, both fail-closed.
- OpenCode provider settings documented from its primary docs.

Exit criteria:
- An over-budget request is refused.
- With a gateway's Postgres stopped, and LiteLLM's Redis too if deployed, the gateway refuses requests within its spend-cache window.
- A search of the box finds no provider key or cloud credential.
- Under the `claude-gateway` and `litellm` gateway profiles, the agent cannot reach `api.anthropic.com` or `api.openai.com` directly.
- With `claude-team`, `claude doctor` reports the remote managed settings as loaded.

### M4, to 2027-01-23

Deliverables:
- `audit` module.
- TUI permission screen and `devbox policy` CLI.
- Signed policy format and root-owned applier.
- EU Cyber Resilience Act (CRA) Annex III classification memo.
- Branch A or branch B recorded.

Exit criteria:
- An agent exec event reaches the bucket within 60 s.
- An agent launched with `sudo -u agent` from a person's SSH session is attributed to the agent.
- An agent launched by systemd is attributed to the agent.
- The person's own commands are attributed to the person.
- The agent cannot stop auditd or change its rules.
- Box credentials cannot delete an object.
- A permission-level or internet change applies with one command.
- A policy that is unsigned or signed by an unknown key is rejected.
- The audit shipper works with internet off.

### M5, to 2027-02-23

Deliverables:
- Both branches: policy from a git repository.
- Branch A: central read-only view of per-box state, spend from the apps gateway and LiteLLM, and audit counts.
- Branch B: `matrix-os` module with a pinned installer, services on loopback and access over Tailscale only.
- Branch B: EU routing gateway profile.
- Branch B: record whether Matrix OS agent traffic passes through the egress proxy and gateway.

Exit criteria:
- Both branches: a signed commit changes a box within 60 s.
- Both branches: every policy change is logged.
- Branch A: the view shows spend from 2 gateway types and audit from at least 3 boxes.
- Branch B: from outside, only SSH is reachable, or nothing on a Tailscale-only box.
- Branch B: the ports listed under [Matrix OS self-host](#matrix-os-self-host) are closed.

### M6, to 2027-03-23

Deliverables:
- Both branches: compliance pack with CRA Art. 14 handling, a software bill of materials (SBOM) from pins, a data protection impact assessment (DPIA) template and a works-council note.
- Both branches: v1.0 of the core.
- Branch B: `governed` EC2 scenario, threat model, Debian container image through `DVB_TEST_IMAGE`, and docs.

Exit criteria:
- Both branches: v1.0 tagged with every negative test green on Ubuntu 24.04.
- Branch A: at least 3 teams run the core and the central view on their own infrastructure, with at least 15 governed boxes in total.
- Branch B: every negative test is green on Debian.

## Regulatory dates and open items

- The CRA Art. 14 vulnerability-reporting duty applies from 2026-09-11. (<https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act>)
- The CRA conformity-assessment regime applies from 2027-12-11. (<https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act>)
- Free and open-source Class I and II products may self-assess when their technical documentation is public. (<https://digital-strategy.ec.europa.eu/en/policies/cra-summary>)

| Open item | Status | Resolved by |
|---|---|---|
| devbox's CRA Annex III class | Unverified | M4 memo |
| Works-council obligations for a person-level audit trail | Unverified | M6 works-council note |
| OpenCode's provider configuration | Unverified | M3 |
| `audit` retention period | Undecided | M4 `audit` module |
| Compliance-mode Object Lock store from an EU provider | Unverified | None in the window |

## Landscape

Facts trace to the linked sources, checked on or before 2026-09-23.

### Development workspace platforms

| Product | Provides | Source |
|---|---|---|
| Coder | Self-hosted workspaces under an AGPL-3.0 core. AI Gateway records prompts, token usage and tool invocations. Agent Firewall allows or denies egress by domain, method and path through nsjail or landjail, configured in `config.yaml` and Terraform. AI Governance needs Coder's commercial licence. | <https://github.com/coder/coder>, <https://coder.com/docs/ai-coder/agent-firewall>, <https://coder.com/docs/ai-coder/ai-governance.md> |
| `coder/boundary` | Standalone egress-allowlist process jail, MIT, with no Coder licence check. | <https://github.com/coder/boundary> |
| Ona (formerly Gitpod) | Cloud agent environments. Ona Guardrails: kernel-level host and port egress control, role-based access and audit logs. OpenAI's acquisition closed on 2026-08-10. | <https://ona.com/cases/ona-guardrails>, <https://ona.com/stories/ona-joins-openai> |
| Daytona | Agent sandboxes with organization roles, an audit-log page and per-sandbox allowlists of up to 10 CIDRs and 100 domains, plus `networkBlockAll`. Core development left the public repository in June 2026; that AGPL-3.0 repository is unmaintained. | <https://github.com/daytonaio/daytona>, <https://www.daytona.io/docs/en/network-limits>, <https://www.daytona.io/docs/en/audit-logs> |
| DevPod | Client-side dev environments, MPL-2.0. Last stable release: v0.6.15 on 2025-03-10. | <https://github.com/loft-sh/devpod/releases> |
| GitHub Codespaces | Managed workspaces. Data residency is GA for GitHub Enterprise in an EU region. Data residency in EFTA countries: effective date unverified. | <https://github.blog/changelog/2026-04-01-codespaces-is-now-generally-available-for-github-enterprise-with-data-residency/> |
| Microsoft Dev Box | Managed dev VMs. Closing-down period starts 2026-09-14; retirement is 2028-09-18; Windows 365 is the named successor. | <https://learn.microsoft.com/en-us/azure/dev-box/dev-box-retirement-guide> |

### Agent sandboxes

| Product | Provides | Source |
|---|---|---|
| Docker Sandboxes (`sbx`) | One VM per agent. Deny-by-default egress through a host-side proxy that injects credentials; credential values never enter the VM. Supported agents include Claude Code, Codex and OpenCode. Organization governance adds central network, filesystem and MCP policies, audit logs and SIEM forwarding. On Linux: Ubuntu 24.04+ with KVM. | <https://docs.docker.com/ai/sandboxes/security/>, <https://docs.docker.com/ai/sandboxes/agents/>, <https://docs.docker.com/ai/sandboxes/governance/>, <https://docs.docker.com/ai/sandboxes/install/> |
| Anthropic sandbox-runtime (`srt`) | Apache-2.0, labelled Beta Research Preview. On Linux, bubblewrap removes the network namespace and forces egress through a domain-allowlist proxy. Documented bypass: domain fronting. | <https://github.com/anthropics/sandbox-runtime> |
| Codex CLI sandbox | Apache-2.0. bubblewrap is the Linux default. Modes: `read-only`, `workspace-write`, `danger-full-access`. | <https://github.com/openai/codex>, <https://learn.chatgpt.com/codex/sandboxing> |
| Claude Code sandbox | bubblewrap on Linux, with a domain allowlist lockable through managed settings. | <https://code.claude.com/docs/en/sandboxing> |
| E2B | Firecracker microVMs, Apache-2.0. `allowInternetAccess` toggle with IP, CIDR and domain allow and deny lists. | <https://github.com/e2b-dev/e2b>, <https://docs.e2b.dev/network/internet-access.md> |
| Runloop Devboxes | Hostname allowlists. AI gateways keep API keys out of the devbox. | <https://docs.runloop.ai/docs/network-policies>, <https://docs.runloop.ai/docs/devboxes/ai-gateways> |

### Hosted agent computers

| Product | Provides | Source |
|---|---|---|
| exe.dev | VMs with a built-in web coding agent named Shelley. | <https://exe.dev> |
| boxes.dev | "Run each Claude Code or Codex chat on its own computer in the cloud." | <https://boxes.dev/> |
| machine0 | Cloud machines; Claude Code and Codex are added with `machine0 integrations connect`. | <https://machine0.io> |
| Boxd | An MCP server that installs into Claude Code, Codex or opencode. | <https://boxd.sh> |
| Agent37 | Persistent sandboxes pre-loaded with agents, including Hermes, OpenClaw and Claude Code. | <https://www.ycombinator.com/companies/agent-37> |
| Manus Cloud Computer | A persistent Ubuntu Server 24.04 VM reachable from a Manus chat. | <https://help.manus.im/en/articles/15392078-understanding-cloud-computer-plans-and-billing> |
| Matrix OS hosted | One Hetzner VPS per user from a stock Ubuntu 24.04 cloud-init image, reprovisioned from an R2 backup on failure. | <https://github.com/HamedMP/matrix-os/blob/5f6d0ce711bf83d24c766b1572c25fd450efe799/specs/070-vps-per-user/spec.md> |
| Hostinger, DigitalOcean | Hostinger lists "Claude Code VPS hosting" and "Codex CLI hosting" KVM products. DigitalOcean lists a "Codex Universal" 1-Click app on Ubuntu 24.04. DigitalOcean's OpenClaw 1-Click runs non-root with a unique gateway token per deployment. | <https://www.hostinger.com/vps/claude-code-hosting>, <https://www.hostinger.com/vps/codex-cli-hosting>, <https://marketplace.digitalocean.com/apps/codex-universal>, <https://www.digitalocean.com/blog/moltbot-on-digitalocean> |
| "Deploy to Hetzner VPS with Claude Code" plugin | Unofficial. Provisions a Hetzner VPS with UFW default-deny except SSH, fail2ban, key-only SSH with root login disabled, automatic security updates and Claude Code. | <https://claude-code-hetzner.vercel.app/> |
| ClawHost | MIT. Provisions OpenClaw or Hermes on Hetzner Cloud VPS with Cloudflare DNS, Let's Encrypt and cloud-init. Runs the agent as a dedicated unprivileged service user. | <https://github.com/antoinersx/clawhost> |

### Personal and team agents

| Product | Provides | Source |
|---|---|---|
| Meta Muse | Consumer personal agent, launched 2026-09-08. Runs on a dedicated "Muse Secure VM" in Meta's cloud. Opt-in Connectors reach email, calendar, payments, health, shopping and smart-home devices. | <https://about.fb.com/news/2026/09/introducing-muse-personal-ai-agent/> |
| Manus | General AI agent, owned by Meta since 2025-12-30. Features include "My Browser" and the Cloud Computer. | <https://www.cnbc.com/2025/12/30/meta-acquires-singapore-ai-agent-firm-manus-china-butterfly-effect-monicai.html>, <https://manus.im> |
| Viktor | "AI coworker" in Slack and Teams with "his own computer in the cloud", connecting to 3,200+ tools. | <https://viktor.com/> |
| Boski | AI agent over X/Twitter DMs, in a beta gated by access code and capped at 200 users. Unverified beyond its X account. | <https://x.com/boski_ai> |
| Microsoft Scout | Always-on personal agent across Microsoft 365, announced 2026-06-02, "powered by OpenClaw open-source technology". | <https://www.microsoft.com/en-us/microsoft-365/blog/2026/06/02/introducing-microsoft-scout-your-always-on-personal-agent> |

### Agent OS stacks and self-hosted agent runtimes

| Product | Provides | Source |
|---|---|---|
| Matrix OS self-host | AGPL-3.0 agent OS installed with `curl -fsSL https://matrix-os.com/install-server.sh \| sudo bash`. | <https://matrix-os.com/docs/self-host>, <https://github.com/HamedMP/matrix-os> |
| OpenClaw | MIT, self-hosted only, with shell, file, browser, Gmail, calendar and messaging access. Gateway auth is mandatory and fail-closed since 2026-01-26. Host installs bind to loopback by default; container images default to an exposed bind. Keeps a metadata-only audit ledger. The official `openclaw-ansible` (MIT) installs with Tailscale, UFW and Docker isolation. | <https://github.com/openclaw/openclaw>, <https://github.com/openclaw/openclaw/issues/1971>, <https://docs.openclaw.ai/gateway/security>, <https://docs.openclaw.ai/gateway/audit>, <https://github.com/openclaw/openclaw-ansible> |
| Hermes Agent | Nous Research, MIT, released 2026-02-25. Backends: local, Docker, SSH, Singularity and Modal. Default: `terminal.backend: local`. Human approval of dangerous commands is configurable through `approvals.mode` (`smart`, `manual`, `off`). | <https://hermes-agent.nousresearch.com/docs/user-guide/security>, <https://github.com/NousResearch/hermes-agent/blob/dad10a78d000b78a69b4035e231aa71d0dc35074/SECURITY.md> |
| Anthropic Managed Agents, self-hosted sandboxes | Tool execution, filesystem and network egress run in the user's infrastructure; orchestration runs at Anthropic. | <https://platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes> |

#### Matrix OS self-host

Repository links are pinned to commit `5f6d0ce`.

- The installer gates the web UI with nginx Basic Auth. (<https://github.com/HamedMP/matrix-os/blob/5f6d0ce711bf83d24c766b1572c25fd450efe799/scripts/install-server.sh#L619-L620>)
- The installer keeps the gateway and code-server on loopback. (<https://github.com/HamedMP/matrix-os/blob/5f6d0ce711bf83d24c766b1572c25fd450efe799/scripts/install-server.sh>, <https://matrix-os.com/docs/self-host>)
- The installer creates a `matrix` system user in the `docker` group. (<https://github.com/HamedMP/matrix-os/blob/5f6d0ce711bf83d24c766b1572c25fd450efe799/scripts/install-server.sh#L398>)
- The operator owns DNS and TLS, server firewalling, OS updates, SSH access, backups, upgrades, edge auth and integration secrets. (<https://matrix-os.com/docs/self-host>)
- Ports to keep closed to the public internet: 3000, 4000, 8787, 8788 and 5432. (<https://matrix-os.com/docs/self-host>)
- Harnesses: Hermes, OpenClaw, Pi, OpenCode, Codex and Claude. (<https://github.com/HamedMP/matrix-os/blob/5f6d0ce711bf83d24c766b1572c25fd450efe799/docs/dev/provider-settings-parity.md#L16>)
- The hosted customer VPS bundles the `claude`, `codex`, `opencode` and `pi` CLIs. (<https://github.com/HamedMP/matrix-os/blob/5f6d0ce711bf83d24c766b1572c25fd450efe799/CHANGELOG.md#L38>)
- The hosted customer VPS installs Hermes and OpenClaw as optional runtimes. (<https://github.com/HamedMP/matrix-os/blob/5f6d0ce711bf83d24c766b1572c25fd450efe799/distro/customer-vps/host-bin/matrix-install-hermes#L13>, <https://github.com/HamedMP/matrix-os/blob/5f6d0ce711bf83d24c766b1572c25fd450efe799/distro/customer-vps/host-bin/matrix-install-openclaw#L15>)
- Hermes and OpenClaw availability on self-host: unverified.
- Organization collaboration V1 uses Clerk membership without RBAC roles. (<https://github.com/HamedMP/matrix-os/blob/5f6d0ce711bf83d24c766b1572c25fd450efe799/specs/124-organization-collaboration/spec.md>)

### Agent policy, budget and access control

| Product | Provides | Source |
|---|---|---|
| Claude Code managed settings | Managed settings, including `/etc/claude-code/managed-settings.json`, apply above user, project, local and `--settings` values. | <https://code.claude.com/docs/en/managed-settings> |
| Claude Code server-managed settings | Web console for Team and Enterprise. "Per-group configurations are not yet supported." Anthropic calls it "a client-side control, not a security boundary". | <https://code.claude.com/docs/en/server-managed-settings> |
| Claude apps gateway | Ships in the `claude` binary from v2.1.195. Model access and managed settings by IdP group; per-user and per-group spend limits. Needs an OIDC IdP and PostgreSQL 14+. "Admin UI: Not available." | <https://code.claude.com/docs/en/claude-apps-gateway>, <https://code.claude.com/docs/en/claude-apps-gateway-spend-limits> |
| LiteLLM proxy | MIT core. Per-key and per-user `max_budget`. Budgets need Postgres. | <https://github.com/BerriAI/litellm>, <https://docs.litellm.ai/docs/proxy/users> |
| Cloudflare AI Gateway | Spend limits by user ID or team; returns 429 at the limit. | <https://developers.cloudflare.com/ai-gateway/features/spend-limits/> |
| Docker AI Governance | Announced 2026-05-12. SAML and SCIM groups, Cedar policies for MCP, domain/IP/CIDR allow and deny rules, and per-decision audit events with SIEM export. | <https://www.docker.com/blog/docker-ai-governance-unlock-agent-autonomy-safely/>, <https://docs.docker.com/ai/sandboxes/mcp-gateway/> |
| Teleport | AGPL-3.0 core with RBAC roles managed in a web UI. The Community Edition licence limits eligible organizations by size. OIDC, SAML and Active Directory SSO are Enterprise-edition only. | <https://github.com/gravitational/teleport>, <https://goteleport.com/docs>, <https://goteleport.com/docs/faq> |
| Tailscale | SSH and ACLs. The configuration audit log is always on with 90-day retention. ACL destinations are IPs, CIDRs, tags, users and host aliases, with no domain names. | <https://tailscale.com/docs/features/tailscale-ssh>, <https://tailscale.com/docs/features/logging/audit-logging>, <https://tailscale.com/kb/1337/acl-syntax> |

## Directions considered

- **D1, open-source personal provisioner:** extend the devbox CLI with pinning, an agent sandbox, egress control, audit and more distros, hosting nothing.
- **D2, hosted personal dev and agent box:** run per-user KVM VMs on devbox-operated Hetzner hosts, each provisioned by devbox.
- **D3, enterprise governed agent workspaces:** a multi-user control plane over devbox boxes with SSO, roles, an admin UI, egress policy, AI budgets and audit.
- **D4, hardened governed base box:** an open-source Debian/Ubuntu box for coding agents and agent OS stacks with a sandbox, an egress allowlist and internet toggle, gateway budgets, off-box audit, and a local permission UI and CLI.
- **D5, personal high-performance agent:** an always-on agent for one developer across chat channels that drives Claude Code, Codex and OpenCode on that developer's hardened box.

## Stack per direction

devbox today runs POSIX sh modules and a Python curses TUI.

| Direction | Language and runtime | Packaging | Control plane | Data store |
|---|---|---|---|---|
| D1 | POSIX sh modules; Python ≥3.8 stdlib curses TUI; nftables, bubblewrap, auditd and Vector as configuration | Existing `install.sh` one-liner and git clone; new `dnf`, `pacman` and `apk` support in `lib/pkg.sh` for new distros | None | TOML manifests and profile files |
| D2 | Guest: devbox run with `--profile FILE --yes`. Host: Incus in VM mode or Proxmox VE | Host image on Hetzner dedicated servers with a ZFS mirror | Coder (AGPL-3.0), with its Incus template adapted to VMs and its WireGuard networking | ZFS replicated between hosts; backups to a Hetzner Storage Box |
| D3 | Box: as D4. Server: Python web service with a server-rendered admin UI and OIDC login | Server as an OCI image plus Compose on the team's infrastructure; box daemon as a devbox module | Self-hosted policy server; a per-box systemd daemon pulls signed policy | PostgreSQL shared with the gateway; audit in S3 Object Lock |
| D4 | Box: POSIX sh plus curses; nftables; bubblewrap or `srt`; smokescreen or Squid; dnsmasq; auditd; Vector; rootless Docker or Podman | Existing installer and new modules | None on the box. Off-box gateway: Claude apps gateway, LiteLLM or Cloudflare AI Gateway | Gateway Postgres; S3 Object Lock bucket in compliance mode |
| D5 | Python 3.14 under uv; one asyncio daemon as a systemd service; `claude`, `codex` and `opencode` workers in bubblewrap | devbox module plus a systemd unit | Telegram bot with outbound polling; small web UI over Tailscale | SQLite for task state and the audit index; LiteLLM with Postgres for budgets |
| Chosen (D4 core + branch A or B) | Box: the D4 stack plus the policy applier and signature check in [UI to change a box's permissions](#ui-to-change-a-boxs-permissions). Branch A central view: static page built by a scheduled Python job | Box: existing `install.sh` and new modules. Central view: one OCI image plus Compose on the team's infrastructure behind the team's SSO proxy | Team-owned policy git repository | Box: signed policy file on local disk. Spend: the gateways' own Postgres. Audit: team-owned S3 Object Lock bucket |

Sources and status:
- Cells without a source below are proposals.
- D1: devbox needs Python 3.8 or newer with `curses`. (`README.md:138`)
- D1: devbox detects `dnf`, `pacman` and `apk` but does not implement them. (`README.md:142`)
- D2: Incus implements virtual machines with QEMU. (<https://linuxcontainers.org/incus/docs/main/explanation/instances/>)
- D2: Coder's registry Incus template provisions Incus system containers. (<https://github.com/coder/registry/tree/main/registry/coder/templates/incus>)
- D2: Coder agents and clients connect over WireGuard tunnels. (<https://coder.com/docs/admin/networking>)
- D2: Hetzner Storage Box supports SFTP, rsync, BorgBackup and Restic. (<https://www.hetzner.com/storage/storage-box>)
