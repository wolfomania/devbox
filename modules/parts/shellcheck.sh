#!/bin/sh
# shellcheck, the shell script linter.
#
#   modules/parts/shellcheck.sh check | install
#
# One tool of the Shell extras bundle, modules/optional/shelltools.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v shellcheck >/dev/null 2>&1 || return 1
	shellcheck --version 2>/dev/null | awk '/^version:/{print "shellcheck", $2}'
}

dvb_install() {
	pkg_install shellcheck
}

dvb_main "$@"
