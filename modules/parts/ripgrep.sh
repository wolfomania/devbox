#!/bin/sh
# ripgrep: rg, a recursive grep that respects .gitignore.
#
# From the GitHub release rather than apt: noble packages 14.1 against an
# upstream on 15.2, a whole major version, and ripgrep is one static binary
# with nothing to gain from being packaged.
#
#   modules/parts/ripgrep.sh check | install
#
# One tool of the Shell toolkit bundle, modules/core/cli.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

ripgrep_triple() {
	case "$DVB_ARCH" in
		amd64) printf 'x86_64-unknown-linux-musl\n' ;;
		arm64) printf 'aarch64-unknown-linux-musl\n' ;;
		*)
			log_err "no ripgrep build for architecture $DVB_ARCH"
			return 1
			;;
	esac
}

dvb_check() {
	command -v rg >/dev/null 2>&1 || return 1
	rg --version 2>/dev/null | head -1 | awk '{print $1, $2}'
}

dvb_install() {
	triple="$(ripgrep_triple)" || return 1
	# A part has no manifest line and so no pin: parts always take the
	# newest release.
	release="$(gh_latest_tag BurntSushi/ripgrep)" || return 1
	dir="ripgrep-${release}-${triple}"
	url="https://github.com/BurntSushi/ripgrep/releases/download/${release}/${dir}.tar.gz"

	fetch_bin_from_tar "$url" "${dir}/rg"
}

dvb_main "$@"
