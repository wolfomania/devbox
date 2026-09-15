#!/bin/sh
# ripgrep: rg, a recursive grep that respects .gitignore.
#
#   modules/parts/ripgrep.sh check | install
#
# One tool of the Shell toolkit bundle, modules/core/cli.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v rg >/dev/null 2>&1 || return 1
	rg --version 2>/dev/null | head -1 | awk '{print $1, $2}'
}

dvb_install() {
	pkg_install ripgrep
}

dvb_main "$@"
