#!/bin/sh
# jq, the JSON processor.
#
#   modules/parts/jq.sh check | install
#
# One tool of the Shell toolkit bundle, modules/core/cli.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v jq >/dev/null 2>&1 || return 1
	jq --version 2>/dev/null | tr - ' '
}

dvb_install() {
	pkg_install jq
}

dvb_main "$@"
