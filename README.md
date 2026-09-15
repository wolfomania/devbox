# devbox

Provision development tools from an interactive menu. Installed tools are
detected and skipped.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/wolfomania/devbox/main/install.sh | sh
```

Run it without `sudo`. devbox escalates with sudo only for the steps that
need root.

- Arrow keys: move
- Space: tick the row under the cursor
- Enter: review the ticked rows, then `y` to install
- Esc or `q`: exit

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

| Category | Module | Selection | Root | Installs |
|---|---|---|---|---|
| Core | `base` | required | yes | gcc, make, curl, wget, unzip, ca-certificates |
| Core | `git` | required | yes | Git |
| Core | `gh` | optional | yes | GitHub CLI |
| Core | `cli` | optional | yes | ripgrep, jq, fzf, tmux, htop, tree |
| Languages | `python` | optional | no | uv |
| Languages | `node` | optional | no | nvm, Node.js |
| Languages | `go` | optional | no | Go |
| Languages | `rust` | optional | no | rustup, Cargo, Clippy, rustfmt |
| Languages | `java` | optional | yes | OpenJDK |
| Languages | `ruby` | optional | yes | Ruby, gem, rake, Bundler |
| Tools | `editors` | optional | yes | Neovim |
| Tools | `db` | optional | yes | psql, sqlite3 |
| DevOps | `docker` | optional | yes | Docker Engine, Compose plugin |
| AI agents | `claude-code` | optional | no | Claude Code |
| AI agents | `codex` | optional | no | Codex CLI; requires `node` |
| Documents | `latex` | optional | yes | TeX Live, latexmk |

Only the required modules are ticked when the screen opens. Space ticks
the rest. Versions and dependencies are defined in
[`manifests/`](manifests).

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
- User tools install under `$HOME`.
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

1. Add a `[[module]]` entry under `manifests/`.
2. Add its script under `modules/`.
3. Define `dvb_check` and `dvb_install` using `lib/module.sh`.
4. Use `pkg_install` for system packages and `env_add` for PATH entries.
5. Run `./tests/modules/run.sh <id>`.

Bundle parts belong in `modules/parts/`.
