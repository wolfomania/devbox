#!/bin/sh
# fd, a fast, friendly find. Debian ships the binary as fdfind because the
# name "fd" was already taken in the archive; linked here so `fd` works as
# everyone expects.
#
#   modules/parts/fd.sh check | install
#
# One tool of the Shell extras bundle, modules/optional/shelltools.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v fdfind >/dev/null 2>&1 || return 1
	fdfind --version 2>/dev/null | awk '{print "fd", $2}'
}

dvb_install() {
	pkg_install fd-find || return 1
	fdfind_bin="$(command -v fdfind)" || return 1
	env_link_bin "$fdfind_bin" fd
}

dvb_main "$@"
