#!/bin/sh
# Claude Code from Anthropic's apt repository where there is root to add it
# with, and from Anthropic's native installer where there is not.
#
# Both paths take the stable channel, so the two agree on what they install.
# The repository carries a few releases less than the installer's default
# channel does, which is what "stable" means here rather than a fault.
#
# The apt path is preferred for the same reason gh, Docker and Temurin take
# theirs: apt then keeps it current on its own. The installer path exists
# because this module has never needed root, and a box without any would
# otherwise lose the module entirely.
#
#   modules/optional/claude-code.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

CLAUDE_KEY_URL="https://downloads.claude.ai/keys/claude-code.asc"

dvb_check() {
	command -v claude >/dev/null 2>&1 || return 1
	printf 'claude %s\n' "$(claude --version 2>/dev/null | awk '{print $1}')"
}

dvb_install() {
	if [ "$DVB_CAN_ROOT" -eq 1 ]; then
		# Anthropic's published key is ASCII-armored; pkg_add_repo dearmors
		# it before apt sees it.
		repo_line="deb [signed-by=/etc/apt/keyrings/claude-code.gpg] https://downloads.claude.ai/claude-code/apt/stable stable main"
		pkg_add_repo "claude-code" "$CLAUDE_KEY_URL" "$repo_line" || return 1
		pkg_install claude-code
		return
	fi

	env_init
	log_dim "  fetching the Claude Code installer"
	fetch_to_stdout "https://claude.ai/install.sh" | bash -s stable >/dev/null 2>&1 || return 1
	[ -x "$DVB_BIN/claude" ] || command -v claude >/dev/null 2>&1
}

dvb_main "$@"
