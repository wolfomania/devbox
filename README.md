# devbox

Provision development tools from an interactive menu. Installed tools are
detected and skipped.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/wolfomania/devbox/main/install.sh | sh
```

Run it as any account that can use `sudo`, or as root. devbox re-runs itself
under sudo and installs everything into a dedicated `exclave` account:

- Creates `exclave` with bash, a home and passwordless sudo, or checks and
  fixes an existing one. A system account named `exclave` is refused.
- Copies the SSH keys of root and of the account that ran sudo into
  `/home/exclave/.ssh/authorized_keys`.
- Log in afterwards with `ssh exclave@<box>`. Set `DVB_ACCOUNT` to use
  another name.

Without any root access, devbox installs for the account that ran it.

- Arrow keys: move
- Space: tick the row under the cursor
- Enter: review the ticked rows, then `y` to install
- Esc or `q`: exit

The letter shortcuts are read by the key's position, so they still work with
a Ukrainian or Russian layout selected.

The menu reopens after each install. The one-line command downloads the
repository to `~/.local/share/devbox/src`.

Run from a clone:

```sh
git clone https://github.com/wolfomania/devbox.git
cd devbox
./install.sh
```

Pass options through the one-line command with `sh -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/wolfomania/devbox/main/install.sh | sh -s -- --yes
```

Set `DVB_REPO` and `DVB_REF` to use another repository or branch.

## Modules

| Category | Module | Selection | Root | Channel | Installs |
|---|---|---|---|---|---|
| System | `swap` | default | yes | `none` | a swapfile, on a box under 2 GiB of memory |
| Core | `base` | required | yes | `apt` | gcc, make, curl, wget, unzip, ca-certificates |
| Core | `git` | required | yes | `apt` | Git |
| Core | `gh` | optional | yes | `apt-vendor` | GitHub CLI |
| Core | `cli` | optional | yes | `mixed` | ripgrep, jq, fzf, tmux, htop, tree |
| Languages | `python` | optional | no | `script` | uv, and CPython 3.14 with `python3` on PATH |
| Languages | `node` | optional | yes | `apt-vendor` | Node.js 24, npm |
| Languages | `go` | optional | no | `release` | Go |
| Languages | `rust` | optional | no | `script` | rustup, Cargo, Clippy, rustfmt |
| Languages | `java` | optional | yes | `apt-vendor` | Eclipse Temurin JDK 25 |
| Languages | `ruby` | optional | yes | `apt` | Ruby, gem, rake, Bundler |
| Languages | `pnpm` | optional | no | `script` | pnpm |
| Tools | `editors` | optional | no | `release` | Neovim |
| Tools | `db` | optional | yes | `apt` | psql, sqlite3 |
| Tools | `shelltools` | optional | yes | `mixed` | shellcheck, bat, fd, delta, direnv, hyperfine, shfmt |
| Tools | `lazygit` | optional | no | `release` | lazygit |
| Tools | `just` | optional | no | `release` | just |
| Tools | `yq` | optional | no | `release` | yq |
| DevOps | `docker` | optional | yes | `apt-vendor` | Docker Engine, Buildx, Compose |
| DevOps | `modal` | optional | no | `uv` | Modal CLI; requires `python` |
| DevOps | `aws` | optional | no | `script` | AWS CLI v2; needs unzip |
| DevOps | `gcloud` | optional | yes | `apt-vendor` | Google Cloud CLI |
| DevOps | `supabase` | optional | no | `release` | Supabase CLI |
| DevOps | `vercel` | optional | no | `npm` | Vercel CLI; requires `node` |
| DevOps | `kubectl` | optional | yes | `apt-vendor` | kubectl |
| DevOps | `k9s` | optional | no | `release` | k9s, a terminal UI for Kubernetes |
| DevOps | `helm` | optional | no | `release` | Helm |
| DevOps | `terraform` | optional | yes | `apt-vendor` | Terraform (BUSL 1.1) |
| DevOps | `opentofu` | optional | no | `release` | OpenTofu (`tofu`) |
| AI agents | `claude-code` | optional | no | `apt-vendor` | Claude Code |
| AI agents | `codex` | optional | no | `npm` | Codex CLI; requires `node` |
| Documents | `latex` | optional | yes | `apt` | TeX Live, latexmk |

Only the required modules are ticked when the screen opens, plus `swap` on
a box with too little memory to build on. Space ticks the rest. Versions,
channels and dependencies are defined in [`manifests/`](manifests).

## Versions and channels

Language runtimes track a major line and let the patch releases float.
Python is pinned to 3.14, Node to 24, Java to Temurin 25, Rust to `stable`;
Go takes whatever go.dev currently calls the newest release. Nothing else
is pinned to a version: every other module installs the latest release.

Where a module installs from is recorded as its channel, and chosen in this
order:

| Channel | When |
|---|---|
| `apt` | Ubuntu's own package is within about a release of upstream, or the tool is a system dependency. |
| `apt-vendor` | The project publishes its own apt repository. apt then keeps the tool current with no further help. |
| `release` | apt is a major version or more behind, and the tool is a self-contained binary or tree. |
| `script`, `npm`, `uv` | The tool's own installer or language package manager is the only supported path. |
| `mixed` | A bundle whose parts do not all come from the same place. |

Snap is not used. snapd needs systemd and, in practice, a privileged
container, so a snap module could not be tested by `./tests/modules/run.sh`.

## Options

| Flag | Action |
|---|---|
| `--list` | Print module status and exit. |
| `-y`, `--yes` | Install the default selection without prompts. |
| `--profile FILE` | Load a selection. |
| `--save-profile FILE` | Save a selection. |
| `--with a,b` | Add modules. |
| `--without a,b` | Remove modules. |
| `--dry-run` | Print the install plan and exit. |

Without a terminal, the selection screen is skipped.

Example:

```sh
./install.sh --profile profiles/example.conf --yes
```

## Requirements

- Debian or Ubuntu for system-package modules.
- Python 3.8 or newer with `curses`.
- `curl` or `wget`.
- `tar` for the one-line install.

`dnf`, `pacman`, `apk`, and `brew` are detected but not implemented. Modules
that do not require root remain available.

## Installation behavior

- System packages require root or `sudo`.
- User tools install under the home of `exclave`, or of the account that ran
  devbox when root is unavailable.
- PATH entries are written to `~/.config/devbox/env.sh`.
- Root-only modules are unavailable when root access is missing.
- Below 2048 MiB of RAM plus swap, interactive runs offer a 2048 MiB
  `/swapfile`. `--yes` does not create it.

Remove the swapfile:

```sh
sudo swapoff /swapfile
sudo rm /swapfile
sudo sed -i '/^\/swapfile /d' /etc/fstab
```

## Module development

Module scripts support:

```sh
./modules/lang/go.sh check
./modules/lang/go.sh install
./modules/lang/go.sh version
```

To add a module:

1. Add a `[[module]]` entry under `manifests/`, with its `pin` and `channel`.
2. Add its script under `modules/`.
3. Define `dvb_check` and `dvb_install` using `lib/module.sh`.
4. Use `pkg_install` for system packages and `env_add` for PATH entries.
5. Run `./tests/modules/run.sh <id>`.

Bundle parts belong in `modules/parts/`.
