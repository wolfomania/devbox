#!/bin/sh
# Node through nvm, so the version is swappable later without root.
# MOD_PIN is the node version; MOD_PIN_EXTRA is the nvm version.

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

	env_add 'export NVM_DIR="$HOME/.nvm"'
	env_add '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
	[ -x "$NVM_DIR_PATH/versions/node/v${MOD_PIN}/bin/node" ]
}
