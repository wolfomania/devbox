#!/bin/sh
# Compiler toolchain and the fetch/extract utilities every other module needs.
#
#   modules/core/base.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

BASE_PACKAGES="build-essential curl wget ca-certificates unzip xz-utils"

dvb_check() {
	for tool in gcc make curl; do
		command -v "$tool" >/dev/null 2>&1 || return 1
	done
	printf 'gcc %s\n' "$(gcc -dumpfullversion 2>/dev/null || gcc -dumpversion 2>/dev/null)"
}

dvb_install() {
	# shellcheck disable=SC2086
	pkg_install $BASE_PACKAGES
}

dvb_main "$@"
