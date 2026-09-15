# devbox

One command to provision a development box. `install.sh` inspects the machine,
shows what is already installed, and installs only what is missing.

Not related to [Jetify's devbox](https://github.com/jetify-com/devbox), which
manages per-project Nix environments.

## Quick start

```sh
curl -fsSL https://raw.githubusercontent.com/wolfomania/devbox/main/install.sh | sh
```

Arrow keys move, space toggles, enter installs, `q` quits.

That one file is the whole entry point. Piped into a shell it downloads the
rest of the repository to `~/.local/share/devbox/src`, re-runs from there, and
reattaches the terminal so the selection screen still works. Flags pass through
with `sh -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/wolfomania/devbox/main/install.sh | sh -s -- --yes
```

From a clone it runs in place and downloads nothing:

```sh
git clone https://github.com/wolfomania/devbox.git
cd devbox
./install.sh
```

Set `DVB_REPO` or `DVB_REF` to bootstrap from a fork or a branch.

## What it does

- Detects OS, architecture, package manager, RAM, free disk and whether root is available.
- Probes every module and reports the installed version. Anything already present is skipped.
- Installs under `$HOME` wherever possible; root is used only for system packages.
- Pins every version in [`manifest.toml`](manifest.toml).
- Writes PATH changes to one file, `~/.config/devbox/env.sh`, sourced from your shell profile.

## Modules

| Module | Category | Default | Root | Installs |
|---|---|---|---|---|
| `base` | core | yes | yes | gcc, make, curl, wget, unzip |
| `git` | core | yes | yes | git |
| `gh` | core | yes | yes | GitHub CLI, from cli.github.com |
| `cli` | core | yes | yes | ripgrep, jq, fzf, tmux, htop, tree |
| `python` | languages | yes | no | uv |
| `node` | languages | yes | no | nvm, node |
| `go` | languages | yes | no | Go, from the official tarball |
| `rust` | languages | yes | no | rustup, cargo, clippy, rustfmt |
| `java` | languages | no | yes | OpenJDK headless |
| `ruby` | languages | no | yes | ruby, gem, rake |
| `latex` | optional | no | yes | TeX Live, latexmk |
| `docker` | optional | no | yes | docker, compose plugin |
| `claude-code` | optional | no | no | Claude Code |
| `codex` | optional | no | no | Codex CLI (requires `node`) |
| `db` | optional | no | yes | psql, sqlite3 |
| `editors` | optional | no | yes | neovim |

## Options

| Flag | Effect |
|---|---|
| `--list` | Print module status and exit. Changes nothing. |
| `-y`, `--yes` | Install the default selection without opening the screen. |
| `--profile FILE` | Read the selection from a profile file. |
| `--save-profile FILE` | Write the selection to a profile file. |
| `--with a,b` | Add modules to the selection. |
| `--without a,b` | Remove modules from the selection. |
| `--dry-run` | Print what would be installed. Changes nothing. |

When stdin is not a terminal, the selection screen is skipped and the default
selection is installed, so piping the script into a shell never hangs.

Provisioning a server over SSH:

```sh
./install.sh --profile profiles/example.conf --yes
```

## Without root

Modules marked **Root** in the table above need a system package manager. When
`install.sh` runs as a normal user with no `sudo`, it lists those modules at
startup, marks them unavailable on the selection screen, and installs the rest
under `$HOME`.

## Low memory

Below 2048 MiB of RAM plus swap, `install.sh` offers to create a 2048 MiB
swapfile at `/swapfile` and register it in `/etc/fstab`. It is offered, never
imposed, and is skipped entirely under `--yes`. Undo with:

```sh
sudo swapoff /swapfile && sudo rm /swapfile
sudo sed -i '/^\/swapfile /d' /etc/fstab
```

## Supported systems

- Debian and Ubuntu, via apt.
- `dnf`, `pacman`, `apk` and `brew` are detected but not yet implemented; those
  boxes can still install every module that does not need root.
- Requires `python3` 3.8 or newer with the `curses` module, and `curl` or `wget`.
- The one-line install also needs `tar`.

## Layout

```
install.sh          entry point: bootstrap, detect, select, install
manifest.toml       module catalogue and pinned versions
lib/                detection, package manager, swap, PATH handling
modules/            one script per module, each defining dvb_check and dvb_install
tui/                selection screen (Python stdlib curses)
plugin/             agent configuration bundled with the AI CLI modules
profiles/           saved selections
```

## Adding a module

1. Add a `[[module]]` block to `manifest.toml`.
2. Create the script it points at, defining two functions:
   - `dvb_check` — print the installed version and return 0, or return 1 if absent.
   - `dvb_install` — install it, returning non-zero on failure.
3. Use `pkg_install` for system packages and `env_add` for PATH changes. Never
   write to a shell profile directly.
