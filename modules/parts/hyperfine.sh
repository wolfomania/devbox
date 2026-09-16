#!/bin/sh
# hyperfine, a command-line benchmarking tool.
#
#   modules/parts/hyperfine.sh check | install
#
# One tool of the Shell extras bundle, modules/optional/shelltools.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v hyperfine >/dev/null 2>&1 || return 1
	hyperfine --version 2>/dev/null | awk '{print $1, $2}'
}

dvb_install() {
	pkg_install hyperfine
}

dvb_main "$@"
