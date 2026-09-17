#!/bin/sh
# fd, a fast, friendly find.
#
# From the GitHub release rather than apt: noble packages 9.0 against an
# upstream on 10.5, a whole major version. It also sidesteps Debian's
# renaming of the binary to fdfind, which every install of the apt package
# had to undo with a symlink.
#
#   modules/parts/fd.sh check | install
#
# One tool of the Shell extras bundle, modules/optional/shelltools.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

fd_triple() {
	case "$DVB_ARCH" in
		amd64) printf 'x86_64-unknown-linux-musl\n' ;;
		arm64) printf 'aarch64-unknown-linux-musl\n' ;;
		*)
			log_err "no fd build for architecture $DVB_ARCH"
			return 1
			;;
	esac
}

dvb_check() {
	command -v fd >/dev/null 2>&1 || return 1
	fd --version 2>/dev/null | awk '{print $1, $2}'
}

dvb_install() {
	triple="$(fd_triple)" || return 1
	release="$(gh_latest_tag sharkdp/fd)" || return 1
	dir="fd-v${release}-${triple}"
	url="https://github.com/sharkdp/fd/releases/download/v${release}/${dir}.tar.gz"

	fetch_bin_from_tar "$url" "${dir}/fd"
}

dvb_main "$@"
