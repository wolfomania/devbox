# devbox module backlog

Candidate modules and work items in priority order for a box where coding
agents run as a separate account without sudo, under egress, budget and audit
controls.

- Repository paths and line numbers are at commit `5d56aaf`.
- Names in code font are module ids. Plain names are work items without a
  module id.
- "Gaps candidate N" is item N under "Candidate modules" in
  `docs/matrix-os-gaps.md`. This table replaces that list's order.
- Branches A and B: [Chosen direction](direction.md#chosen-direction).
- Months M1–M6 and release rules:
  [6-month roadmap](direction.md#6-month-roadmap).
- Non-goals: [Non-goals in the window](direction.md#non-goals-in-the-window).

| Order | Module | Installs or configures | Evidence | Month |
|---|---|---|---|---|
| 1 | `pins` | Pinned version and SHA-256 check for the 9 `release` modules; a pinned version or a recorded exemption for each of the 14 `pin = "latest"` entries; install steps under `timeout` with bounded retries | Gaps candidate 1. `lib/pkg.sh:176` resolves the newest release tag. `manifests/*.toml`: 9 entries with `channel = "release"`, 14 with `pin = "latest"`. | M1 |
| 2 | `agent` | A login account with no sudo and no `docker` group membership; coding-agent CLIs installed for it | `lib/paths.sh:29-32` derives install paths from `$HOME`. | M1 |
| 3 | `governed` | Account mode that removes `NOPASSWD:ALL` from human accounts and logs break-glass sudo through a separate account | `lib/account.sh:87` grants `NOPASSWD:ALL`. | M1 |
| 4 | `sandbox` | bubblewrap, socat and the AppArmor `bwrap` userns profile on Ubuntu 24.04+ | Gaps candidate 2. [sandbox-runtime](https://github.com/anthropics/sandbox-runtime) and [Codex](https://github.com/openai/codex) sandbox with bubblewrap on Linux. | M1 |
| 5 | `claude-code` | Pinned, checksum-verified install in place of the `curl \| bash` fallback | `modules/optional/claude-code.sh:36` pipes `https://claude.ai/install.sh` into `bash`. | M1 |
| 6 | `egress` | nftables table keyed on UIDs: agent internet on/off, named system-UID exemptions, forward proxy (smokescreen or Squid) with an allowlist, `DOCKER-USER` rule, GitHub and package-registry presets, the LLM gateway as the only model host under `claude-gateway` and `litellm` | `modules/system/firewall.sh:34` runs `ufw default allow outgoing`. [nftables](https://wiki.nftables.org/wiki-nftables/index.php/Matching_packet_metainformation) matches output per UID with `meta skuid`. [Internet on/off per box](direction.md#internet-onoff-per-box). | M2 |
| 7 | agent resolver | dnsmasq that answers only allowlisted names for the agent UID and feeds an nftables set | [dnsmasq(8)](https://manpages.debian.org/testing/dnsmasq-base/dnsmasq.8.en.html): `--address=/#/`, `--server=/<domain>/`. [Internet on/off per box](direction.md#internet-onoff-per-box). | M2 |
| 8 | rootless containers | Rootless Docker or Podman for `agent` | `modules/optional/docker.sh:57` adds the installing user to `docker`. [Roles and permissions](direction.md#roles-and-permissions). [Rootless mode](https://docs.docker.com/engine/security/rootless/). | M2 |
| 9 | `sshd` | Key-only SSH login; root login disabled | `lib/` and `modules/` set neither `PasswordAuthentication` nor `PermitRootLogin`. | M2 |
| 10 | `tailscale` | Tailscale with Tailscale SSH and ACLs; ingress over the tailnet in place of open ports | [Tailscale SSH](https://tailscale.com/docs/features/tailscale-ssh) is available on all plans. | M2 |
| 11 | `opencode` | OpenCode CLI | Gaps candidate 4. [anomalyco/opencode](https://github.com/anomalyco/opencode) is MIT. | M2 |
| 12 | negative tests | Checks in `tests/vps/assert.sh`: egress blocked, DNS tunnels blocked, direct provider API access blocked, over-budget requests refused, requests refused with the gateway's Postgres stopped and LiteLLM's Redis too if deployed, no sudo or `docker` for `agent`, no human `NOPASSWD` under `governed`, audit attribution, audit tamper resistance, unsigned policy rejected | Module tests check only that `check` fails, `install` succeeds and `check` prints a version (`AGENTS.md:66-67`). | M2–M4 |
| 13 | `llm-gateway` | The [gateway profiles](#gateway-profiles); a reference VM running the Claude apps gateway and LiteLLM with Postgres, secrets in mode `0600` env files; a reference apps-gateway policy that sets `managedSourcesBehavior: "merge"` or delivers the item 14 hooks and OpenTelemetry settings; `claude-team` docs telling the customer to set `managedSourcesBehavior: "merge"` in the claude.ai console | [AI API budget](direction.md#ai-api-budget). [Agent policy, budget and access control](direction.md#agent-policy-budget-and-access-control). | M3 |
| 14 | `audit` | auditd rules keyed on `uid` and `euid`, locked with `-e 2`; Claude Code hooks, `allowManagedHooksOnly` and OpenTelemetry pinned in `/etc/claude-code/managed-settings.json`; prompt content off; Vector shipping to S3 Object Lock in compliance mode, with bucket credentials in a mode `0600` env file | [Traceability of agent and person](direction.md#traceability-of-agent-and-person). [Managed settings precedence](#managed-settings-precedence). | M4 |
| 15 | `policy` | Signed policy files; a root-owned applier that runs `ssh-keygen -Y verify`; a TUI permission screen for permission level, internet, allowlist, budget remaining and recent person and agent events; a `devbox policy` CLI | `tui/app.py` has no permission screen. [UI to change a box's permissions](direction.md#ui-to-change-a-boxs-permissions). | M4 |
| 16 | policy repo | Boxes pull signed policy commits from a git repository; extends item 15 | — | M5 |
| 17 | central view | Read-only view of box state, spend from the item 13 gateways and audit counts from the item 14 bucket; policy roles Owner (signs policy), Member (uses boxes without root) and Auditor (reads the view) | With spend limits configured, the Claude apps gateway's PostgreSQL holds durable spend tables ([Claude apps gateway](https://code.claude.com/docs/en/claude-apps-gateway)). | A: M5–M6 |
| 18 | `matrix-os` | Matrix OS self-host on this base: services on loopback, access over Tailscale, the `matrix` account removed from the `docker` group and placed under agent controls, Matrix OS's Postgres run rootless (item 8) or as a native service | [Matrix OS self-host](direction.md#matrix-os-self-host). `matrix-restore.service` starts Postgres with `docker run` as `matrix` ([`scripts/install-server.sh:530-543`](https://github.com/HamedMP/matrix-os/blob/5f6d0ce711bf83d24c766b1572c25fd450efe799/scripts/install-server.sh#L530-L543)). Whether Matrix OS agents run through `egress` and `llm-gateway` is unverified. | B: M5 |
| 19 | EU routing | Gateway profile to Amazon Bedrock or Google Cloud in an EU region; OpenCode to EU-hosted open-weight endpoints | [AI API budget](direction.md#ai-api-budget). The [IONOS sovereign pattern](https://docs.ionos.com/cloud/ai/mcp-server/use-cases/sovereign-ai-workflow.md) needs a client with a custom base URL, such as OpenCode. | B: M5 |
| 20 | Debian test image | Container tier on Debian through `DVB_TEST_IMAGE` | `tests/modules/run.sh:23` defaults to `ubuntu:24.04`. | B: M6 |
| 21 | `swap` | `vm.swappiness=10` with the swapfile | Gaps candidate 3. `lib/` and `modules/` set no swappiness. | After M6 |
| 22 | `zellij` | Terminal multiplexer | Gaps candidate 4. | After M6 |
| 23 | `zsh` | zsh with pinned Powerlevel10k and plugins | Gaps candidate 5. | After M6 |
| 24 | `debug` | Part set: strace, lsof, rsync, dnsutils, netcat-openbsd, zip | Gaps candidate 6. | After M6 |

## Gateway profiles

Item 13 configures these client profiles. Fail-closed settings and sources:
[AI API budget](direction.md#ai-api-budget).

| Profile | Client | Model host | devbox budget cap | What fails closed |
|---|---|---|---|---|
| `claude-gateway` | Claude Code signed in to a Claude apps gateway | Claude apps gateway | Per user and per group | Requests while the gateway's spend store is unreachable (`enforcement.fail_closed_on_error: true`) |
| `litellm` | Codex, OpenCode, and Claude Code without an IdP | LiteLLM proxy | Per key (`max_budget`) | Budgeted requests (503) when neither Redis nor Postgres can verify spend (`fail_closed_budget_enforcement: true`) |
| `claude-team` | Claude Code on a Claude Team or Enterprise login, with no base-URL override | Anthropic | None | Nothing |

## Managed settings precedence

claude.ai and a Claude apps gateway deliver managed settings that rank above
`/etc/claude-code/managed-settings.json`
([managed settings](https://code.claude.com/docs/en/managed-settings)).

Under the default `managedSourcesBehavior: "first-wins"`, when either
delivers a policy key:

- Claude Code reads from the file only the keys read from every admin source,
  such as `sandbox.network.allowManagedDomainsOnly` and
  `sandbox.network.strictAllowlist`.
- Claude Code ignores the file's hooks and `allowManagedHooksOnly`.

Under either setting
([server-managed settings](https://code.claude.com/docs/en/server-managed-settings)):

- From v2.1.223, `env` merges per variable: the file supplies each variable
  the higher sources leave unset.
- The `OTEL_EXPORTER_OTLP_*`, `OTEL_LOG_*` and `OTEL_LOGS_EXPORTER` variables
  apply as one unit from the highest source that sets any of them.

Under `"merge"`:

- Claude Code applies every admin source, combined by kind of key. Requires
  v2.1.242+.
- Claude Code reads `managedSourcesBehavior` only from the highest-ranked
  source that carries it or a policy key.

## Host-hardening items from `docs/matrix-os-gaps.md`

Each item maps to backlog items:

- Secret env files at mode `0600`: items 13 and 14.
- Service `MemoryHigh`/`MemoryMax`, restart policies and start timeouts:
  every systemd unit that an item adds.
- Swappiness: item 21.
- Install steps under `timeout` with bounded retries: item 1.
- Cloudflare tunnel ingress: item 10 (Tailscale).
- Log shipping: item 14, with Vector in place of Loki and Grafana Alloy.
