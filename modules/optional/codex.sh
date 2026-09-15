#!/bin/sh
# Codex CLI from npm. Depends on the node module, which the runner installs first.

dvb_check() {
	command -v codex >/dev/null 2>&1 || return 1
	printf 'codex %s\n' "$(codex --version 2>/dev/null | awk '{print $NF}')"
}

dvb_install() {
	if ! command -v npm >/dev/null 2>&1; then
		# The node module is installed in the same run, so pick it up from the
		# managed env rather than relying on a shell restart.
		[ -f "$DVB_ENV_FILE" ] && . "$DVB_ENV_FILE"
	fi

	command -v npm >/dev/null 2>&1 || {
		log_err "npm not found; the Node module must be installed first"
		return 1
	}

	log_dim "  npm install -g @openai/codex"
	npm install -g @openai/codex >/dev/null 2>&1
}
