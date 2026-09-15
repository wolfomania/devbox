#!/bin/sh
# Compiler toolchain and the fetch/extract utilities every other module needs.
#
#   modules/core/base.sh check | install | version
#
# A bundle: one line in the selection screen, one script per tool in
# modules/parts. Each of those installs on its own.
. "$(dirname -- "$0")/../../lib/module.sh"

BASE_PARTS="build-essential curl wget ca-certificates unzip xz"

dvb_check() {
	# shellcheck disable=SC2086
	dvb_check_parts $BASE_PARTS
}

dvb_install() {
	# shellcheck disable=SC2086
	dvb_install_parts $BASE_PARTS
}

dvb_main "$@"
