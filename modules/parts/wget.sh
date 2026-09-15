#!/bin/sh
# wget, the fallback fetcher on boxes without curl.
#
#   modules/parts/wget.sh check | install
#
# One tool of the Build essentials bundle, modules/core/base.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v wget >/dev/null 2>&1 || return 1
	wget --version 2>/dev/null | head -1 | awk '{print $1, $3}'
}

dvb_install() {
	pkg_install wget
}

dvb_main "$@"
