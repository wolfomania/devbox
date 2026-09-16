#!/bin/sh
# Shell extras: linters and quality-of-life tools for working in a terminal.
# An apt bundle, like modules/core/cli.sh; the packaged versions lag upstream
# on Ubuntu 24.04, which is fine for tools like these.
#
#   modules/optional/shelltools.sh check | install | version
#
# A bundle: one line in the selection screen, one script per tool in
# modules/parts. Each of those installs on its own.
. "$(dirname -- "$0")/../../lib/module.sh"

SHELLTOOLS_PARTS="shellcheck bat fd delta direnv hyperfine shfmt"

dvb_check() {
	# shellcheck disable=SC2086
	dvb_check_parts $SHELLTOOLS_PARTS
}

dvb_install() {
	# shellcheck disable=SC2086
	dvb_install_parts $SHELLTOOLS_PARTS
}

dvb_main "$@"
