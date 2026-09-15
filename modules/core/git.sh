#!/bin/sh
# Git, plus one global default that is set only when the user has no opinion.
#
#   modules/core/git.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v git >/dev/null 2>&1 || return 1
	git --version 2>/dev/null | awk '{print $1, $3}'
}

dvb_install() {
	pkg_install git || return 1

	if [ -z "$(git config --global --get init.defaultBranch 2>/dev/null)" ]; then
		git config --global init.defaultBranch main
		log_dim "  set init.defaultBranch = main"
	fi
}

dvb_main "$@"
