# devbox

One command to provision a development box. `install.sh` inspects the machine,
shows what is already installed, and installs only what is missing.

## Quick start

```sh
curl -fsSL https://raw.githubusercontent.com/wolfomania/devbox/main/install.sh | sudo sh
```

Arrow keys move, space toggles, enter installs. The selection screen
reopens when the install finishes, whether it succeeded or not, so you can
pick the next thing; `esc` or `q` leaves.

That one file is the whole entry point. Piped into a shell it downloads the
rest of the repository to `~/.local/share/devbox/src`, re-runs from there, and
reattaches the terminal so the selection screen still works. Flags pass through
with `sh -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/wolfomania/devbox/main/install.sh | sudo sh -s -- --yes
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
- Pins every version in [`manifests/`](manifests).
- Writes PATH changes to one file, `~/.config/devbox/env.sh`, sourced from your shell profile.

## Modules

The catalogue is split across `manifests/`, one file per category, read in
filename order. The numeric prefix sets where the category appears on screen.

| File | Module | Default | Root | Installs |
|---|---|---|---|---|
| `10-core.toml` | `base` | yes | yes | gcc, make, curl, wget, unzip |
| | `git` | yes | yes | git |
| | `gh` | yes | yes | GitHub CLI, from cli.github.com |
| | `cli` | yes | yes | ripgrep, jq, fzf, tmux, htop, tree |
| `20-languages.toml` | `python` | yes | no | uv |
| | `node` | yes | no | nvm, node |
| | `go` | yes | no | Go, from the official tarball |
| | `rust` | yes | no | rustup, cargo, clippy, rustfmt |
| | `java` | no | yes | OpenJDK headless |
| | `ruby` | no | yes | ruby, gem, rake |
| `30-tools.toml` | `editors` | no | yes | neovim |
| | `db` | no | yes | psql, sqlite3 |
| `40-devops.toml` | `docker` | no | yes | docker, compose plugin |
| `50-ai.toml` | `claude-code` | no | no | Claude Code |
| | `codex` | no | no | Codex CLI (requires `node`) |
| `60-docs.toml` | `latex` | no | yes | TeX Live, latexmk |

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
manifests/          module catalogue, one .toml per category
lib/                detection, package manager, swap, PATH handling
modules/            one script per module, each runnable on its own
modules/parts/      one script per tool, for the modules that are bundles
tui/                selection screen (Python stdlib curses)
plugin/             agent configuration bundled with the AI CLI modules
profiles/           saved selections
tests/              selection screen, modules in containers, modules on a VPS
```

## Running one module

Every module is a script that installs one thing and stops:

```sh
./modules/lang/go.sh check      # print the installed version, or exit 1
./modules/lang/go.sh install    # install it, then exit
./modules/lang/go.sh version    # print the version it is pinned to
```

`install.sh` runs modules through these same commands. The pinned version
comes from the manifest either way, so a module never carries a second copy
of a version number.

A module whose menu line covers several independently useful tools is a
bundle. Its parts live in `modules/parts`, one tool each, and run the same way:

```sh
./modules/parts/ripgrep.sh install     # just ripgrep
./modules/core/cli.sh install          # all six tools of the Shell toolkit
./modules/core/cli.sh check            # "4 of 6 present", and a non-zero exit
```

A bundle installs every part even after one fails, and names the ones that
did, so a missing package takes out one tool rather than the whole line.
`base`, `cli` and `db` are bundles today.

## Adding a module

1. Add a `[[module]]` block to the manifest file for its category. The
   `category` comes from that file's `[manifest]` block; a module only sets its
   own to override it.
2. Create the script it points at. It sources `lib/module.sh`, defines two
   functions, and calls `dvb_main "$@"`:
   - `dvb_check` — print the installed version and return 0, or return 1 if absent.
   - `dvb_install` — install it, returning non-zero on failure.
3. Use `pkg_install` for system packages and `env_add` for PATH changes. Never
   write to a shell profile directly.
4. Test it: `./tests/modules/run.sh <id>` installs it on its own in a
   throwaway container and checks the result. No new test file is needed; the
   runner reads the manifest.

A bundle instead defines its parts and delegates:

```sh
CLI_PARTS="ripgrep jq fzf tmux htop tree"
dvb_check()   { dvb_check_parts $CLI_PARTS; }
dvb_install() { dvb_install_parts $CLI_PARTS; }
```

Each part is a script in `modules/parts` that sets `DVB_UNLISTED=1` before
sourcing `lib/module.sh`, because it has no manifest entry and so no pin.

Dependencies cross files freely: `requires = ["node"]` on `codex` in
`50-ai.toml` pulls `node` from `20-languages.toml` and installs it first.

## Adding a category

Create `manifests/<order>-<name>.toml`:

```toml
[manifest]
category = "security"   # id used by requires and --with
title = "Security"      # heading on the selection screen
order = 45              # position; ties fall back to filename order

[[module]]
id = "..."
```

Duplicate module ids are rejected across files. `DVB_MANIFEST` overrides the
catalogue location, and still accepts a single `.toml` file instead of a
directory.
