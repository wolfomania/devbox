#!/bin/sh
# tree, for looking at a directory shape quickly.
#
#   modules/parts/tree.sh check | install
#
# One tool of the Shell toolkit bundle, modules/core/cli.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v tree >/dev/null 2>&1 || return 1
	tree --version 2>/dev/null | awk '{print $1, $2}'
}

dvb_install() {
	pkg_install tree
}

dvb_main "$@"
