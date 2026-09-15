#!/bin/sh
# tmux, so a long install survives a dropped connection.
#
#   modules/parts/tmux.sh check | install
#
# One tool of the Shell toolkit bundle, modules/core/cli.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v tmux >/dev/null 2>&1 || return 1
	tmux -V 2>/dev/null
}

dvb_install() {
	pkg_install tmux
}

dvb_main "$@"
