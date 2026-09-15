#!/bin/sh
# Rust through rustup. The toolchain lands in ~/.rustup and ~/.cargo.
# This is the largest module by far; see size_mb in the manifest.
#
#   modules/lang/rust.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v rustc >/dev/null 2>&1 || return 1
	rustc --version 2>/dev/null | awk '{print $1, $2}'
}

dvb_install() {
	env_init
	log_dim "  fetching rustup, toolchain $MOD_PIN"
	fetch_to_stdout "https://sh.rustup.rs" |
		sh -s -- -y --no-modify-path --default-toolchain "$MOD_PIN" --profile default >/dev/null || return 1

	env_add '[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"'
	[ -x "$HOME/.cargo/bin/rustc" ]
}

dvb_main "$@"
