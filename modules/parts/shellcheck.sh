#!/bin/sh
# shellcheck, the shell script linter.
#
# From the GitHub release rather than apt: noble packages 0.9.0 against an
# upstream on 0.11.0, and the checks this repository's own scripts are read
# with live in that gap.
#
#   modules/parts/shellcheck.sh check | install
#
# One tool of the Shell extras bundle, modules/optional/shelltools.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

shellcheck_arch() {
	case "$DVB_ARCH" in
		amd64) printf 'x86_64\n' ;;
		arm64) printf 'aarch64\n' ;;
		*)
			log_err "no shellcheck build for architecture $DVB_ARCH"
			return 1
			;;
	esac
}

dvb_check() {
	command -v shellcheck >/dev/null 2>&1 || return 1
	shellcheck --version 2>/dev/null | awk '/^version:/{print "shellcheck", $2}'
}

dvb_install() {
	arch="$(shellcheck_arch)" || return 1
	release="$(gh_latest_tag koalaman/shellcheck)" || return 1
	# Both .tar.gz and .tar.xz are published; the gz one is what
	# fetch_bin_from_tar unpacks, and saves the module needing xz.
	url="https://github.com/koalaman/shellcheck/releases/download/v${release}/shellcheck-v${release}.linux.${arch}.tar.gz"

	fetch_bin_from_tar "$url" "shellcheck-v${release}/shellcheck"
}

dvb_main "$@"
