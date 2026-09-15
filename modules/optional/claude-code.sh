#!/bin/sh
# Claude Code via Anthropic's native installer. Installs under $HOME.

dvb_check() {
	command -v claude >/dev/null 2>&1 || return 1
	printf 'claude %s\n' "$(claude --version 2>/dev/null | awk '{print $1}')"
}

dvb_install() {
	env_init
	log_dim "  fetching the Claude Code installer"
	fetch_to_stdout "https://claude.ai/install.sh" | bash >/dev/null 2>&1 || return 1
	[ -x "$DVB_BIN/claude" ] || command -v claude >/dev/null 2>&1
}
