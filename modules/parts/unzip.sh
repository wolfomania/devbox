#!/bin/sh
# unzip, for the release archives that are not tarballs.
#
#   modules/parts/unzip.sh check | install
#
# One tool of the Build essentials bundle, modules/core/base.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v unzip >/dev/null 2>&1 || return 1
	unzip -v 2>/dev/null | head -1 | awk '{print $1, $2}'
}

dvb_install() {
	pkg_install unzip
}

dvb_main "$@"
