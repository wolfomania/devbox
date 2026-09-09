# devbox

A record of my development box environment, kept so that it can be reproduced on another
machine. The box is a GCP Compute Engine VM in zone `europe-central2-a` — 4 vCPU, 15 GiB RAM,
96 GB root disk — running Ubuntu 24.04.4 LTS (Noble Numbat).

This repository holds documentation only. There is no code to run and nothing to install from
here; it is the reference you read while rebuilding.

## Contents

- [`docs/inventory.md`](docs/inventory.md) — the full environment inventory: every language
  runtime, compiler, CLI tool and toolchain directory, with exact versions. Snapshot taken
  2026-09-09.

## Not in apt

Most of the box comes from Ubuntu packages and can be restored with `apt install`. The
following do not, and have to be installed outside the package manager. Reinstall these by
hand after the apt layer is in place.

- **Go** — installed from the official tarball into `/usr/local/go`, currently go1.26.4
  linux/amd64. There is no Go apt package on this box, so do not expect `apt install golang` to
  reproduce it.
- **nvm** — 0.40.1, installed by its own install script into `~/.nvm`. It provides node
  v24.18.0, which in turn provides npm 11.16.0, pnpm 11.9.0 and corepack 0.35.0.
- **rustup** — 1.29.0, installed from rustup.rs into `~/.cargo` and `~/.rustup`. Provides rustc
  1.96.1, cargo 1.96.1, rustfmt 1.9.0-stable, clippy 0.1.96 and rust-analyzer, on a single
  `stable-x86_64-unknown-linux-gnu` toolchain.
- **uv** — 0.11.26 in `~/.local/bin`, plus a uv-managed CPython 3.8.13 under
  `~/.local/share/uv`.
- **pipx apps** — yt-dlp 2026.7.4, running on Python 3.12.3.
- **npm globals** — supabase 2.114.0 and vercel 54.20.1, installed into the nvm node tree at
  `~/.nvm/versions/node/v24.18.0/lib/node_modules`.
- **uv tools** — modal 1.5.5.
- **pip3 --user** — playwright 1.61.0.

Two things worth knowing before you start:

- `pnpm setup` was never run on this box, so `~/.local/share/pnpm/bin` is not on PATH and there
  are no pnpm globals to restore.
- The cargo and `~/go/bin` install sets are both empty. Nothing was installed with
  `cargo install` or `go install`.
