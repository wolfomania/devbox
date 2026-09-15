#!/bin/sh
# Client tools only. No database server is installed or started.

DB_PACKAGES="postgresql-client sqlite3"

dvb_check() {
	command -v psql >/dev/null 2>&1 || return 1
	command -v sqlite3 >/dev/null 2>&1 || return 1
	psql --version 2>/dev/null | awk '{print "psql", $3}'
}

dvb_install() {
	# shellcheck disable=SC2086
	pkg_install $DB_PACKAGES
}
