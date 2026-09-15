#!/bin/sh
# Client tools only. No database server is installed or started.
#
#   modules/optional/db.sh check | install | version
#
# A bundle: one line in the selection screen, one script per tool in
# modules/parts. Each of those installs on its own.
. "$(dirname -- "$0")/../../lib/module.sh"

DB_PARTS="postgresql-client sqlite3"

dvb_check() {
	# shellcheck disable=SC2086
	dvb_check_parts $DB_PARTS
}

dvb_install() {
	# shellcheck disable=SC2086
	dvb_install_parts $DB_PARTS
}

dvb_main "$@"
