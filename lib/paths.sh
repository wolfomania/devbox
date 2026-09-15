#!/bin/sh
# PATH and shell-profile management.
#
# devbox writes exactly one file, ~/.config/devbox/env.sh, and adds a single
# source line to the user's shell profiles. Uninstalling is deleting that file
# and that line; no module ever appends to .bashrc directly.

DVB_ENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/devbox"
DVB_ENV_FILE="$DVB_ENV_DIR/env.sh"
DVB_PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/devbox"
DVB_BIN="$HOME/.local/bin"

env_init() {
	mkdir -p "$DVB_ENV_DIR" "$DVB_BIN" "$DVB_PREFIX"
	[ -f "$DVB_ENV_FILE" ] && return 0

	cat > "$DVB_ENV_FILE" <<'SNIPPET'
# Managed by devbox. Edit at your own risk; devbox appends to this file.
case ":$PATH:" in
	*":$HOME/.local/bin:"*) ;;
	*) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH
SNIPPET
}

# Append a line to the managed env file, once.
env_add() {
	env_init
	grep -qxF "$1" "$DVB_ENV_FILE" 2>/dev/null && return 0
	printf '%s\n' "$1" >> "$DVB_ENV_FILE"
}

# Source the managed env file into the current shell, if it exists.
#
# Probes and installs run in subshells that have not been through a login
# shell, so without this a tool devbox installed a moment ago looks missing.
load_env() {
	[ -f "$DVB_ENV_FILE" ] || return 0
	# shellcheck source=/dev/null
	. "$DVB_ENV_FILE" >/dev/null 2>&1 || true
}

# Make every interactive shell source the managed env file.
env_link_profiles() {
	env_init
	line=". \"$DVB_ENV_FILE\"  # devbox"

	for profile in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
		[ -f "$profile" ] || continue
		grep -qF "$DVB_ENV_FILE" "$profile" 2>/dev/null && continue
		printf '\n%s\n' "$line" >> "$profile"
		log_dim "  hooked $profile"
	done
}

# Symlink a binary into ~/.local/bin so it lands on PATH without a shell restart.
env_link_bin() {
	target="$1"
	name="${2:-$(basename "$1")}"
	env_init
	ln -sf "$target" "$DVB_BIN/$name"
}
