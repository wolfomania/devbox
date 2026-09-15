#!/bin/sh
# psql, the PostgreSQL command line client. No server is installed.
#
#   modules/parts/postgresql-client.sh check | install
#
# One tool of the Database clients bundle, modules/optional/db.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v psql >/dev/null 2>&1 || return 1
	psql --version 2>/dev/null | awk '{print "psql", $3}'
}

dvb_install() {
	pkg_install postgresql-client
}

dvb_main "$@"
