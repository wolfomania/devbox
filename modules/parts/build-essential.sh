#!/bin/sh
# The C and C++ toolchain: gcc, g++, make and the standard headers.
#
#   modules/parts/build-essential.sh check | install
#
# One tool of the Build essentials bundle, modules/core/base.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v gcc >/dev/null 2>&1 || return 1
	command -v make >/dev/null 2>&1 || return 1
	printf 'gcc %s\n' "$(gcc -dumpfullversion 2>/dev/null || gcc -dumpversion 2>/dev/null)"
}

dvb_install() {
	pkg_install build-essential
}

dvb_main "$@"
