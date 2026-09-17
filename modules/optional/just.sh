#!/bin/sh
# just, a command runner for project recipes, from its GitHub release tarball.
# The musl build is used so the binary needs no particular glibc version; a
# bare binary either way, so no root is needed.
#
# MOD_PIN is "latest", which is what the manifest says, or an exact version.
# The asset carries the version in its name, so the newest release has to be
# looked up before the URL can be written.
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
	release="$(mod_release casey/just)" || return 1
	asset="just-${release}-${triple}.tar.gz"
	url="https://github.com/casey/just/releases/download/${release}/${asset}"

	fetch_bin_from_tar "$url" just
}

dvb_main "$@"
