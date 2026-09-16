#!/bin/sh
# direnv, per-directory environment variables loaded on cd.
#
#   modules/parts/direnv.sh check | install
#
# One tool of the Shell extras bundle, modules/optional/shelltools.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v direnv >/dev/null 2>&1 || return 1
	printf 'direnv %s\n' "$(direnv version 2>/dev/null)"
}

dvb_install() {
	pkg_install direnv
}

dvb_main "$@"
