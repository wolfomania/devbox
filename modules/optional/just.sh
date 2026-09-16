#!/bin/sh
# just, a command runner for project recipes, from its GitHub release tarball.
# The musl build is used so the binary needs no particular glibc version; a
# bare binary either way, so no root is needed.
#
#   modules/optional/just.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

just_triple() {
	case "$DVB_ARCH" in
		amd64) printf 'x86_64-unknown-linux-musl\n' ;;
		arm64) printf 'aarch64-unknown-linux-musl\n' ;;
		*)
			log_err "no just build for architecture $DVB_ARCH"
			return 1
			;;
	esac
}

dvb_check() {
	command -v just >/dev/null 2>&1 || return 1
	just --version 2>/dev/null | awk '{print $1, $2}'
}

dvb_install() {
	triple="$(just_triple)" || return 1
	asset="just-${MOD_PIN}-${triple}.tar.gz"
	url="https://github.com/casey/just/releases/download/${MOD_PIN}/${asset}"
	tmp="$(mktemp -d)"

	log_dim "  fetching $asset"
	if ! fetch_to_file "$url" "$tmp/$asset"; then
		rm -rf "$tmp"
		return 1
	fi

	tar -C "$tmp" -xzf "$tmp/$asset" just || {
		rm -rf "$tmp"
		return 1
	}

	env_init
	install -m 0755 "$tmp/just" "$DVB_BIN/just"
	status=$?
	rm -rf "$tmp"
	[ "$status" -eq 0 ] && [ -x "$DVB_BIN/just" ]
}

dvb_main "$@"
