#!/bin/sh
# htop, the process viewer.
#
#   modules/parts/htop.sh check | install
#
# One tool of the Shell toolkit bundle, modules/core/cli.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v htop >/dev/null 2>&1 || return 1
	htop --version 2>/dev/null | head -1
}

dvb_install() {
	pkg_install htop
}

dvb_main "$@"
