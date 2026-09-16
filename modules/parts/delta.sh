#!/bin/sh
# delta, a syntax-highlighting pager for git and diff output. Packaged as
# git-delta; the binary itself is called delta.
#
#   modules/parts/delta.sh check | install
#
# One tool of the Shell extras bundle, modules/optional/shelltools.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v delta >/dev/null 2>&1 || return 1
	delta --version 2>/dev/null | awk '{print $1, $2}'
}

dvb_install() {
	pkg_install git-delta
}

dvb_main "$@"
