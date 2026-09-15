#!/bin/sh
# The shell utilities assumed by the rest of this setup.
#
#   modules/core/cli.sh check | install | version
#
# A bundle: one line in the selection screen, one script per tool in
# modules/parts. Each of those installs on its own.
. "$(dirname -- "$0")/../../lib/module.sh"

CLI_PARTS="ripgrep jq fzf tmux htop tree"

dvb_check() {
	# shellcheck disable=SC2086
	dvb_check_parts $CLI_PARTS
}

dvb_install() {
	# shellcheck disable=SC2086
	dvb_install_parts $CLI_PARTS
}

dvb_main "$@"
