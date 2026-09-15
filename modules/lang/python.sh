#!/bin/sh
# Python via uv: one binary that manages interpreters, venvs and tools.
# Installs entirely under $HOME, so no root is needed.
#
#   modules/lang/python.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v uv >/dev/null 2>&1 || return 1
	uv --version 2>/dev/null | awk '{print $1, $2}'
}

dvb_install() {
	if ! command -v python3 >/dev/null 2>&1 && [ "$DVB_CAN_ROOT" -eq 1 ]; then
		pkg_install python3 python3-venv || return 1
	fi

	env_init
	log_dim "  fetching uv $MOD_PIN"
	fetch_to_stdout "https://astral.sh/uv/${MOD_PIN}/install.sh" |
		env UV_INSTALL_DIR="$DVB_BIN" INSTALLER_NO_MODIFY_PATH=1 sh >/dev/null || return 1

	env_add "# uv installs tools into ~/.local/bin"
	[ -x "$DVB_BIN/uv" ]
}

dvb_main "$@"
