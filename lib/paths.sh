#!/bin/sh
# PATH and shell-profile management.
#
# devbox writes exactly one file, ~/.config/devbox/env.sh, and adds a single
# source line to the user's shell profiles. Uninstalling is deleting that file
# and that line; no module ever appends to .bashrc directly.

# Derived from HOME, which install.sh may retarget when it is run under sudo,
# so these live in a function that can be called again.
# HOME is not guaranteed to be set. A command sent over SSM, a cron job and a
# systemd unit all arrive without one, and every path below hangs off it, so
# work it out from the passwd database rather than let `set -u` kill the run.
paths_ensure_home() {
	[ -n "${HOME:-}" ] && return 0

	HOME="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)"
	if [ -z "$HOME" ] && [ "$(id -u)" -eq 0 ]; then
		HOME=/root
	fi
	[ -n "$HOME" ] || {
		printf 'devbox: HOME is unset and uid %s has no home directory\n' "$(id -u)" >&2
		exit 1
	}
	export HOME
}

paths_refresh() {
	paths_ensure_home
	DVB_ENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/devbox"
	DVB_ENV_FILE="$DVB_ENV_DIR/env.sh"
	DVB_PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/devbox"
	DVB_BIN="$HOME/.local/bin"
}
paths_refresh

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

	# A bash-only snippet in env.sh is a syntax error under dash, and dash
	# answers a syntax error in a sourced file by killing the shell outright
	# rather than returning non-zero. The `|| true` below cannot catch that,
	# and probes and installs run inside subshells that would die with it,
	# reporting every module as missing. So prove the file is survivable in a
	# throwaway child first; the trailing `:` keeps a merely non-zero exit
	# from being mistaken for a fatal one.
	if ! (. "$DVB_ENV_FILE" >/dev/null 2>&1; :); then
		return 0
	fi

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
