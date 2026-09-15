#!/bin/sh
# Node through nvm, so the version is swappable later without root.
# MOD_PIN is the node version; MOD_PIN_EXTRA is the nvm version.
#
#   modules/lang/node.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

NVM_DIR_PATH="$HOME/.nvm"

dvb_check() {
	command -v node >/dev/null 2>&1 || return 1
	printf 'node %s\n' "$(node --version 2>/dev/null | tr -d v)"
}

dvb_install() {
	if [ ! -s "$NVM_DIR_PATH/nvm.sh" ]; then
		log_dim "  fetching nvm $MOD_PIN_EXTRA"
		fetch_to_stdout "https://raw.githubusercontent.com/nvm-sh/nvm/v${MOD_PIN_EXTRA}/install.sh" |
			env PROFILE=/dev/null bash >/dev/null 2>&1 || return 1
	fi

	log_dim "  installing node $MOD_PIN"
	NVM_DIR="$NVM_DIR_PATH"
	export NVM_DIR
	# nvm is a shell function, so it has to run inside bash with nvm.sh sourced.
	bash -c '. "$NVM_DIR/nvm.sh" && nvm install "$1" && nvm alias default "$1"' _ "$MOD_PIN" >/dev/null 2>&1 || return 1

	# nvm.sh is a bash/zsh script. Sourcing it from dash is not merely
	# useless, it is a syntax error, and dash answers a syntax error in a
	# sourced file by killing the shell. env.sh is sourced by every probe and
	# every install, so an unguarded nvm line here breaks all of devbox.
	# Put node on PATH directly, and load nvm only where it actually runs.
	env_add 'export NVM_DIR="$HOME/.nvm"'
	env_add "export PATH=\"\$NVM_DIR/versions/node/v${MOD_PIN}/bin:\$PATH\""
	env_add '[ -n "${BASH_VERSION:-}${ZSH_VERSION:-}" ] && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" || true'
	[ -x "$NVM_DIR_PATH/versions/node/v${MOD_PIN}/bin/node" ]
}

dvb_main "$@"
