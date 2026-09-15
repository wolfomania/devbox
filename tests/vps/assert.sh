#!/bin/sh
# Runs on the test instance after install.sh has finished. Verifies the result
# the way a returning user would see it, not the way the installer sees it.
#
# Inputs (environment):
#   DVB_EXPECT  space separated commands that must resolve
#   DVB_USER    the account devbox was installed for
#   DVB_SRC     the source tree, when one was shipped
#   DVB_FLAGS   the flags the scenario installed with, replayed for the
#               idempotence check
#
# Exits non-zero if any check fails. Every check runs; the script does not stop
# at the first failure, so one run reports everything that is wrong.

set -u

: "${DVB_EXPECT:?}"
: "${DVB_USER:?}"
DVB_SRC="${DVB_SRC:-}"
DVB_FLAGS="${DVB_FLAGS:---yes}"

FAILURES=0

pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

# Run a command as the target user in a shell they would actually get.
#   login        reads ~/.profile
#   interactive  reads ~/.bashrc
as_login()       { runuser -l "$DVB_USER" -c "$1" 2>/dev/null; }
as_interactive() { runuser -u "$DVB_USER" -- bash -ic "$1" 2>/dev/null; }

# --- the tools are on PATH in a fresh shell --------------------------------
#
# This deliberately does not use install.sh --list. The installer's own probe
# sources ~/.config/devbox/env.sh by hand before checking, so it reports a tool
# as present even when the shell wiring that a real user depends on is broken.

check_login_shell() {
	printf '\nlogin shell (~/.profile)\n'
	for tool in $DVB_EXPECT; do
		if resolved="$(as_login "command -v $tool")" && [ -n "$resolved" ]; then
			# Discard stderr: tools that spell it differently (go version,
			# not go --version) would otherwise report their usage error
			# as if it were a version string.
			version="$(as_login "$tool --version 2>/dev/null | head -1")"
			pass "$(printf '%-8s %s' "$tool" "${version:-$resolved}")"
		else
			fail "$tool not found in a login shell"
		fi
	done
}

check_interactive_shell() {
	printf '\ninteractive shell (~/.bashrc)\n'
	for tool in $DVB_EXPECT; do
		if resolved="$(as_interactive "command -v $tool")" && [ -n "$resolved" ]; then
			pass "$tool"
		else
			fail "$tool not found in an interactive shell"
		fi
	done
}

# --- the managed env file and its hooks ------------------------------------

check_env_file() {
	printf '\nmanaged environment\n'
	env_file="$(as_login 'printf %s "${XDG_CONFIG_HOME:-$HOME/.config}/devbox/env.sh"')"

	if as_login "[ -f '$env_file' ]"; then
		pass "env.sh exists at $env_file"
	else
		fail "env.sh missing at $env_file"
		return
	fi

	hooked=0
	for profile in .profile .bashrc .zshrc; do
		if as_login "grep -q devbox/env.sh \$HOME/$profile 2>/dev/null"; then
			pass "~/$profile sources env.sh"
			hooked=$((hooked + 1))
		fi
	done
	[ "$hooked" -gt 0 ] || fail "no shell profile sources env.sh"
}

# --- re-running changes nothing --------------------------------------------

check_idempotent() {
	printf '\nidempotence\n'
	[ -n "$DVB_SRC" ] && [ -d "$DVB_SRC" ] || {
		printf '  skip  no source tree on the box\n'
		return
	}

	output="$(as_login "cd '$DVB_SRC' && ./install.sh --list" || true)"
	if printf '%s' "$output" | grep -q '^  ok'; then
		pass "--list reports installed modules"
	else
		fail "--list reports nothing installed after a successful install"
	fi

	# Replay the scenario's own flags. A bare --yes would re-select every
	# default the scenario deliberately excluded and look like a failure.
	second="$(as_login "cd '$DVB_SRC' && ./install.sh $DVB_FLAGS" || true)"
	if printf '%s' "$second" | grep -qi 'nothing to do'; then
		pass "a second --yes run is a no-op"
	else
		fail "a second --yes run was not a no-op"
		printf '%s\n' "$second" | tail -5 | sed 's/^/        /'
	fi
}

# --- nothing was left behind for root --------------------------------------

check_no_root_pollution() {
	printf '\nisolation\n'
	if [ "$DVB_USER" != "root" ] && [ -f /root/.config/devbox/env.sh ]; then
		fail "installing as $DVB_USER wrote into /root"
	else
		pass "no stray state in /root"
	fi
}

main() {
	printf 'asserting for user %s\n' "$DVB_USER"
	check_login_shell
	check_interactive_shell
	check_env_file
	check_idempotent
	check_no_root_pollution

	printf '\n'
	if [ "$FAILURES" -eq 0 ]; then
		printf 'all checks passed\n'
		exit 0
	fi
	printf '%d check(s) failed\n' "$FAILURES"
	exit 1
}

main
