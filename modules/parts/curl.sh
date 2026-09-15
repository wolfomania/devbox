#!/bin/sh
# curl, the fetcher every other module reaches for first.
#
#   modules/parts/curl.sh check | install
#
# One tool of the Build essentials bundle, modules/core/base.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v curl >/dev/null 2>&1 || return 1
	curl --version 2>/dev/null | head -1 | awk '{print $1, $2}'
}

dvb_install() {
	pkg_install curl
}

dvb_main "$@"
