#!/bin/sh
# Modal CLI, the client for Modal's serverless compute platform. Installed with
# uv as an isolated tool, so it carries its own Python and dependencies rather
# than landing in whatever interpreter happens to be on the box.
#
#   modules/optional/modal.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v modal >/dev/null 2>&1 || return 1
	printf 'modal %s\n' "$(modal --version 2>/dev/null | awk '{print $NF}')"
}

dvb_install() {
	if ! command -v uv >/dev/null 2>&1; then
		# The python module is installed in the same run, so pick uv up from
		# the managed env rather than relying on a shell restart.
		[ -f "$DVB_ENV_FILE" ] && . "$DVB_ENV_FILE"
	fi

	command -v uv >/dev/null 2>&1 || {
		log_err "uv not found; the Python module must be installed first"
		return 1
	}

	env_init
	log_dim "  uv tool install modal==$MOD_PIN"
	env UV_TOOL_BIN_DIR="$DVB_BIN" uv tool install --force "modal==$MOD_PIN" \
		>/dev/null 2>&1 || return 1

	[ -x "$DVB_BIN/modal" ]
}

dvb_main "$@"
