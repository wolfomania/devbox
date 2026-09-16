#!/bin/sh
# bat, a cat with syntax highlighting. Debian ships the binary as batcat
# because the name "bat" was already taken in the archive; linked here so
# `bat` works as everyone expects.
#
#   modules/parts/bat.sh check | install
#
# One tool of the Shell extras bundle, modules/optional/shelltools.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v batcat >/dev/null 2>&1 || return 1
	batcat --version 2>/dev/null | awk '{print $1, $2}'
}

dvb_install() {
	pkg_install bat || return 1
	batcat_bin="$(command -v batcat)" || return 1
	env_link_bin "$batcat_bin" bat
}

dvb_main "$@"
