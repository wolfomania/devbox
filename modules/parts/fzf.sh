#!/bin/sh
# fzf, the interactive fuzzy finder.
#
#   modules/parts/fzf.sh check | install
#
# One tool of the Shell toolkit bundle, modules/core/cli.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v fzf >/dev/null 2>&1 || return 1
	printf 'fzf %s\n' "$(fzf --version 2>/dev/null | awk '{print $1}')"
}

dvb_install() {
	pkg_install fzf
}

dvb_main "$@"
