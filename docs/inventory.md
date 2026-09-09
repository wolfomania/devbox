# Dev Box Environment Inventory

Snapshot taken 2026-09-09. This is a point-in-time record of everything installed on
the dev box, kept so the environment can be rebuilt on another machine. Versions are
recorded exactly as reported by the tools themselves.

Each section also notes what is deliberately *not* installed, which is useful when
deciding whether something was skipped on purpose or simply never set up.

## Base image

- Ubuntu 24.04.4 LTS (Noble Numbat) — ID=ubuntu, VERSION_ID=24.04, codename noble
- Kernel 6.17.0-1021-gcp (#24~24.04.1-Ubuntu SMP, built 2026-07-07), x86_64 / dpkg arch amd64
- GCP Compute Engine VM, not a container — systemd-detect-virt reports `google`, hypervisor KVM, DMI vendor Google Compute Engine, PID 1 is systemd
- Zone europe-central2-a. 4 vCPU Intel Xeon @ 2.20GHz, 15 GiB RAM, 96 GB root disk
- Kernel package family `linux-gcp`; base metapackages `ubuntu-minimal`, `ubuntu-standard`, `ubuntu-server`, `build-essential`
- 1021 apt packages installed (ii); 110 marked manual

### Apt repositories

- `/etc/apt/sources.list` — empty
- deb822 `ubuntu.sources` — mirror europe-central2-a.gce.clouds.archive.ubuntu.com, suites noble / noble-updates / noble-backports, all four components, plus security.ubuntu.com noble-security
- `github-cli.list` — cli.github.com/packages stable main
- `google-chrome.sources`
- `google-cloud-ops-agent.list` — google-cloud-ops-agent-noble-all
- `google_osconfig_managed.list` — empty
- No PPAs

### Snaps and system services

- Snaps: core24 20260410, snapd 2.76.3, google-cloud-cli 583.0.0 (classic). Flatpak not installed.
- GCP agents / enabled services: google-guest-agent, google-osconfig-agent, google-cloud-ops-agent, google-startup-scripts, google-shutdown-scripts, cloud-init, chrony, earlyoom, atop, docker, containerd
- User groups include: docker, google-sudoers, lxd, adm

## Shell

- `$SHELL` = /bin/bash
- bash 5.2.21(1)-release
- dash — present
- tmux 3.4
- screen 4.09.01
- `/etc/shells`: sh, bash, rbash, dash, screen, tmux
- Dotfiles present: `~/.bashrc`, `~/.profile`, `~/.zshrc` (orphaned — zsh not installed), `~/.config/fish` (orphaned — fish not installed)

Not installed: zsh, fish, oh-my-zsh, starship, oh-my-posh, atuin, zoxide, direnv, nushell.

## Compilers and build tools

- gcc 13.3.0 (Ubuntu 13.3.0-6ubuntu2~24.04.1) — also gcc-13
- g++ 13.3.0 — also g++-13
- build-essential 12.10ubuntu1
- GNU Make 4.3
- ld (GNU binutils) 2.42

Not installed: clang/clang++, cmake, ninja, autoconf, automake, libtool, pkg-config, gdb, lldb, valgrind, ccache, meson.

## Python

- python3 3.12.3 — `/usr/bin/python3`, apt package python3.12 3.12.3-1ubuntu0.15
- python3-dev 3.12.3
- python3-venv 3.12.3
- pip / pip3 24.0 — system, dist-packages
- pipx 1.4.3
- uv 0.11.26 — `~/.local/bin/uv`
- uvx 0.11.26
- python3.8 3.8.13 — uv-managed, `~/.local/share/uv/python/cpython-3.8.13-linux-x86_64-gnu`, symlinked to `~/.local/bin/python3.8`

System pip3 carries 85 packages, all Ubuntu / cloud-init stock (boto3 1.34.46, Twisted 24.3.0,
cryptography 41.0.7, rich 13.7.1, PyYAML 6.0.1). Nothing there needs manual reinstall.

Not installed: `python` / `python2` alias, poetry, pyenv, conda/mamba, virtualenv, pipenv, hatch, ruff, black, mypy.

## JavaScript and TypeScript

- node v24.18.0 — installed via nvm
- npm 11.16.0
- npx 11.16.0
- pnpm 11.9.0 — nvm bin; content store at `~/.local/share/pnpm/store` (394M)
- corepack 0.35.0
- nvm 0.40.1 — default `lts/*` -> v24.18.0; v24.18.0 is the only version installed

`pnpm setup` was never run, so `~/.local/share/pnpm/bin` is not on PATH and no pnpm globals exist.

Not installed: yarn, bun, deno, fnm, volta, global tsc / ts-node.

## Go

- go1.26.4 linux/amd64 — `/usr/local/go`, manual tarball install, **not** apt
- gofmt — ships with go1.26.4
- `GOPATH=/home/kulyz/go` — module cache only; `~/go/bin` does not exist, no `go install` binaries

Not installed: golangci-lint, dlv.

## Rust

rustup-managed, living in `~/.cargo` and `~/.rustup`.

- rustc 1.96.1 (31fca3adb 2026-06-26)
- cargo 1.96.1
- rustup 1.29.0
- rustfmt 1.9.0-stable
- clippy (cargo-clippy / clippy-driver) 0.1.96
- rust-analyzer
- Toolchains: stable-x86_64-unknown-linux-gnu (default, and the only one)
- Components: cargo, clippy, rust-docs, rust-std, rustc, rustfmt

`cargo install --list` is empty — no cargo-installed binaries.

## JVM

- java — openjdk 21.0.12 2026-07-21
- javac 21.0.12 — openjdk-21-jdk-headless 21.0.12+8-1~24.04
- jshell, jar — JDK 21
- JVM dirs: java-21-openjdk-amd64, java-1.21.0-openjdk-amd64, default-java

Not installed: Maven, Gradle, Kotlin, Scala, sbt, Groovy, Ant, Clojure, Leiningen, SDKMAN.

## Ruby, Perl, Tcl

- ruby 3.2.3 — apt package ruby3.2 3.2.3-1ubuntu0.24.04.8
- gem 3.4.20
- irb 1.6.2
- rake 13.0.6
- perl 5.38.2
- cpan 1.64
- tclsh 8.6.14

91 gems are installed, all Ruby 3.2 stdlib defaults plus stock debug, minitest, rake, rbs,
matrix, prime, net-*, power_assert — nothing user-installed. bundler 2.4.19 is present only as
a default gem; there is no `bundle` on PATH.

Not installed: PHP, composer, rbenv, rvm, cpanm.

## Languages not installed

lua / luajit / luarocks, R / Rscript, julia, swift, dart / flutter, zig, nim, crystal,
elixir / mix / iex, erlang, ghc / cabal / stack, ocaml / opam, dotnet / mono / csc, racket,
sbcl, guile, haxe, v, odin.

`~/.dotnet` exists but holds only 276K of stale corefx/cryptography config — there is no .NET
SDK or runtime.

## LaTeX and TeX

TeX Live 2023, Debian-packaged.

- pdfTeX 3.141592653-2.6-1.40.25 (TeX Live 2023/Debian), kpathsea 6.3.5
- tlmgr revision 69653 (2024-01-31), installation `/usr/share/texlive`

There are no TL scheme or collection records, because this is a distro-packaged TeX Live
rather than a tug.org installer install. The apt package list below is the replication source,
not tlmgr.

Paths:

- `TEXMFDIST` — /usr/share/texlive/texmf-dist
- `TEXMFHOME` — /home/kulyz/texmf
- `TEXMFLOCAL` — /usr/local/share/texmf

Binaries present: tex, pdftex, pdflatex, latex, lualatex, bibtex, makeindex, kpsewhich, tlmgr,
texhash, mktexlsr, dvips, dvipdfmx, texdoc, dvisvgm.

Binaries absent: xelatex, latexmk, biber, context.

Installed packages:

- texlive-base 2023.20240207-1
- texlive-binaries 2023.20230311.66589-9build3
- texlive-latex-base 2023.20240207-1
- texlive-latex-recommended 2023.20240207-1
- texlive-latex-extra 2023.20240207-1
- texlive-fonts-recommended 2023.20240207-1
- texlive-fonts-extra 2023.20240207-1
- texlive-fonts-extra-links 2023.20240207-1
- texlive-lang-english 2023.20240207-1
- texlive-pictures 2023.20240207-1
- texlive-plain-generic 2023.20240207-1
- tex-common 6.18
- tex-gyre 20180621-6
- lmodern 2.005-1
- tipa 2:1.3-21
- preview-latex-style 13.2-1
- dvisvgm 3.2.1+ds-1build1

Minimal reinstall set — the manually-marked packages, which pull the rest in as dependencies:

```
sudo apt install \
  texlive-latex-base \
  texlive-latex-recommended \
  texlive-latex-extra \
  texlive-fonts-recommended \
  texlive-fonts-extra \
  texlive-lang-english
```

Not installed: texlive-xetex, texlive-luatex, texlive-science, texlive-publishers,
texlive-bibtex-extra, texlive-extra-utils, texlive-metapost, texlive-humanities,
texlive-lang-cyrillic, texlive-lang-european, texlive-full, latexmk, biber, chktex.

Verified resolvable: `article.cls`, `amsmath.sty`, `tikz.sty`, `unicode-math.sty`.

## Doc and PDF toolchain

- poppler-utils 24.02.0-1ubuntu9.9 — pdftotext, pdfinfo
- poppler-data 0.4.12-1
- mupdf-tools 1.23.10+ds1-1build3
- libgs10 / libgs10-common / libgs-common 10.02.1~dfsg1-0ubuntu7.8 — Ghostscript **libraries only**; the `gs` binary and the `ghostscript` package are not installed

Fonts: roughly 60 `fonts-*` packages — full Noto including CJK, emoji and extra; DejaVu;
Liberation; TeX Gyre plus math; Latin Modern; STIX; SIL Gentium / Charis / Andika; GFS Greek;
Google web fonts; Inter; Lato; Open Sans; Roboto; Font Awesome. Manually marked:
fonts-liberation, fonts-noto, fonts-noto-cjk, fonts-noto-color-emoji, fonts-freefont-ttf,
fonts-ipafont-gothic, fonts-tlwg-loma-otf, fonts-unifont, fonts-wqy-zenhei, xfonts-cyrillic,
xfonts-scalable.

Not installed: pandoc, ghostscript (gs), imagemagick, inkscape, graphviz, plantuml,
mermaid-cli, asymptote, gnuplot, typst, quarto, qpdf, pdftk, libreoffice.

## Git and version control

- git 2.43.0
- gh 2.95.0 (2026-06-17) — from the cli.github.com apt repo

Not installed: git-lfs, glab, hub, tig, lazygit, delta, difftastic, gitui, mercurial,
subversion, jj, pre-commit.

## Core CLI utilities

- curl 8.5.0 — OpenSSL 3.0.13, nghttp2 1.59.0, brotli, zstd
- wget 1.21.4
- jq 1.7
- ripgrep (rg) 14.1.0
- tmux 3.4
- screen 4.09.01
- htop 3.3.0
- atop 2.10.0
- tar (GNU) 1.35
- unzip 6.00
- zip (Info-ZIP) 3.0
- gzip 1.12
- bzip2 1.0.8
- xz 5.4.5
- zstd 1.5.5
- net-tools 2.10
- iproute2 6.1.0
- findutils 4.9.0 — xargs
- Xvfb — present, no `$DISPLAY` set
- google-chrome 150.0.7871.46

`/usr/local/bin` is empty.

Not installed: httpie, xh, yq, fx, fd, fzf, ag, ack, bat, eza, lsd, tree, zoxide, btop, ncdu,
duf, dust, glances, procs, sd, hyperfine, tldr, broot, yazi, ranger, mc, parallel, pv,
sqlite3 CLI.

## Editors

- vim / vi 9.1 — compiled 2026-08-24
- nano 7.2
- GNU ed 1.20.1
- VS Code Remote CLI (`code`) 1.127.0 — `~/.vscode-server` and `~/.vscode` present, python debugpy extension 2026.6.0

Not installed: nvim, emacs, micro, helix, codium.

## Containers

- docker 29.1.3 — apt package docker.io, 29.1.3-0ubuntu3~24.04.2
- docker compose plugin 2.40.3+ds1-0ubuntu1~24.04.1 — docker-compose-v2
- containerd / ctr 2.2.1

Not installed: docker-compose v1, buildx, podman, buildah, nerdctl, kubectl, helm, minikube,
kind, k9s, skaffold, kustomize, kubectx, stern, dive.

## Infrastructure as code

None installed — terraform, opentofu, ansible, packer, vagrant, pulumi, terragrunt and tflint
are all absent.

## Cloud CLIs

- gcloud (Google Cloud SDK) 583.0.0 — snap google-cloud-cli, classic confinement
- gsutil 5.37
- bq 2.1.38
- vercel 54.20.1 — npm global
- supabase 2.114.0 — npm global
- modal 1.5.5 — uv tool

Not installed: aws, az, doctl, flyctl, netlify, wrangler, heroku, railway, firebase, eksctl,
s3cmd.

## Networking

- OpenSSH_9.6p1 Ubuntu-3ubuntu13.19 — OpenSSL 3.0.13
- rsync 3.2.7 — protocol 31
- scp — OpenSSH
- nc — OpenBSD netcat (Debian 1.226-1ubuntu2)
- tcpdump 4.99.4
- dig / host / nslookup — BIND 9.18.39-0ubuntu0.24.04.7
- mtr 0.95
- ping — iputils 20240117
- ip / ss — iproute2 6.1.0
- netstat — net-tools 2.10
- ufw 0.36.2
- iptables 1.8.10 — nf_tables

Not installed: sshfs, mosh, tailscale, wireguard, openvpn, nmap, ncat, socat, whois,
traceroute, iperf3, cloudflared, ngrok.

## Media and files

- yt-dlp 2026.07.04 — via pipx
- playwright 1.61.0 — pip --user, with greenlet 3.5.3, pillow 12.3.0, pyee 13.0.1
- pdftotext / pdfinfo 24.02.0

Not installed: ffmpeg, ffprobe, sox, youtube-dl, exiftool, imagemagick, 7z, rclone, restic,
borg, duplicity, rsnapshot.

## Databases

- psql 16.15 — apt package postgresql-client-16
- pg_dump 16.15
- Python `sqlite3` module — SQLite 3.45.1, library only

Not installed: sqlite3 CLI, mysql / mariadb client, mongosh, redis-cli, duckdb,
clickhouse-client.

## Linters and formatters

- gofmt — bundled with Go 1.26.4
- rustfmt 1.9.0-stable
- clippy-driver 0.1.96

Not installed: shellcheck, shfmt, hadolint, yamllint, ruff, black, flake8, mypy, pylint,
eslint, prettier, tsc, golangci-lint, clang-format, markdownlint, vale, codespell, actionlint,
tflint, pre-commit.

## AI CLIs

- Claude Code 2.1.265 — `~/.local/bin/claude`, versions dir `~/.local/share/claude/versions/2.1.265`; plugin cache at `~/.claude/plugins/cache/claude-plugins-official/exa/{3.3.10,3.4.1}`
- GitHub Copilot CLI — shim present under `~/.vscode-server/data/User/globalStorage/github.copilot-chat/copilotCli/copilot`, but **broken**: it points at a VS Code server dir that no longer exists, so any `copilot` invocation fails with `node: not found`

Not installed: codex, gemini, aider, ollama, llm, cursor-agent, opencode, goose, sgpt, amp,
crush.

## Global packages to reinstall on a new box

- npm global (`~/.nvm/versions/node/v24.18.0/lib/node_modules`): supabase 2.114.0, vercel 54.20.1 (also exposes `vc`); plus bundled npm 11.16.0 and corepack 0.35.0
- pipx: yt-dlp 2026.7.4 — on Python 3.12.3
- uv tools: modal 1.5.5
- pip3 --user: playwright 1.61.0
- pnpm global: empty. cargo: empty. `~/go/bin`: absent.

## Toolchain directories in the home dir

- `~/.nvm` — 585M — nvm 0.40.1, node v24.18.0
- `~/.cargo` — 20M — rustup-managed cargo home
- `~/.rustup` — 1.4G — stable toolchain only
- `~/.local/bin` — 93M — uv, uvx, yt-dlp, modal, playwright, python3.8, claude, code, env, env.fish, ta (a local tmux-attach shell script)
- `~/.local/share/uv` — 117M — uv-managed CPython 3.8.13
- `~/.cache/uv` — 2.4G — uv cache
- `~/go` — 213M — `pkg/` module cache only, no `bin/`
- `~/.npm` — 2.8G — npm cache
- `~/.local/share/pnpm` — 394M — store plus an empty bin dir
- `~/.dotnet` — 276K — stale crypto config only

Absent: `~/.pyenv`, `~/.rbenv`, `~/.rvm`, `~/.sdkman`, `~/.asdf`, `~/.mise`, `~/.config/mise`,
`~/.bun`, `~/.deno`, `~/.gradle`, `~/.m2`, `~/.yarn`, `~/.nuget`, `~/.stack`, `~/.cabal`,
`~/.ghcup`, `~/.opam`, `~/.composer`, `~/.gem`, `~/.conda`, `~/miniconda3`, `~/anaconda3`,
`~/.jenv`, `~/.goenv`, `~/.nodenv`, `~/.tfenv`.

## PATH note

PATH is heavily prepended by VS Code Remote — `~/.vscode-server/.../debugCommand`,
`.../copilotCli`, `.../remote-cli` — then `~/.local/bin`, `~/.cargo/bin`,
`~/.nvm/versions/node/v24.18.0/bin`. `/usr/local/go/bin` and `/snap/bin` appear only after the
system dirs. `~/.local/bin` and `/snap/bin` are each duplicated.
