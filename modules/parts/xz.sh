#!/bin/sh
# xz, for .tar.xz archives.
#
#   modules/parts/xz.sh check | install
#
# One tool of the Build essentials bundle, modules/core/base.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v xz >/dev/null 2>&1 || return 1
	xz --version 2>/dev/null | head -1 | awk '{print $1, $4}'
}

dvb_install() {
	pkg_install xz-utils
}

dvb_main "$@"
