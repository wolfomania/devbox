#!/bin/sh
# shfmt, a shell script formatter.
#
#   modules/parts/shfmt.sh check | install
#
# One tool of the Shell extras bundle, modules/optional/shelltools.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v shfmt >/dev/null 2>&1 || return 1
	printf 'shfmt %s\n' "$(shfmt --version 2>/dev/null | sed 's/^v//')"
}

dvb_install() {
	pkg_install shfmt
}

dvb_main "$@"
