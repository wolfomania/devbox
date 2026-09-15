#!/bin/sh
# The sqlite3 command line shell.
#
#   modules/parts/sqlite3.sh check | install
#
# One tool of the Database clients bundle, modules/optional/db.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v sqlite3 >/dev/null 2>&1 || return 1
	printf 'sqlite3 %s\n' "$(sqlite3 --version 2>/dev/null | awk '{print $1}')"
}

dvb_install() {
	pkg_install sqlite3
}

dvb_main "$@"
