#!/bin/sh
# pnpm from its standalone installer, entirely under $HOME. No root and no
# Node are needed: the installer fetches a self-contained pnpm binary and
# only calls out to Node afterwards, for packages that want it.
#
# MOD_PIN is "latest", which is what the manifest says, or an exact version
# to hold at. pnpm is a tool rather than a runtime, so it takes the newest
# release; the installer does that by itself when $PNPM_VERSION is not set.
#
# The installer script itself is not version-pinned either way: it is
# re-fetched from get.pnpm.io on every install and could change behaviour out
# from under this module.
#
# The installer's own `pnpm setup` step insists on picking a shell config
# file to append PATH to, and fails outright if it cannot infer one (this
# module runs from POSIX sh, with no controlling shell to infer). Rather than
# let it write to a real profile, it is pointed at a throwaway file for that
# step. That diversion relies on the installer honouring $ENV for a
# SHELL=/bin/sh invocation, which is the installer's behaviour today but is
# not asserted here, so $HOME is also pointed at the temp directory for the
# installer's run: $PNPM_HOME is passed explicitly, so the real $HOME is
# never needed for the install to work, and a future installer that ignores
# $ENV still has no real profile within reach. The managed env file carries
# PATH instead, same as every other module here.
#
#   modules/lang/pnpm.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v pnpm >/dev/null 2>&1 || return 1
	printf 'pnpm %s\n' "$(pnpm --version 2>/dev/null)"
}

dvb_install() {
	env_init
	pnpm_home="$DVB_PREFIX/pnpm"
	tmp="$(mktemp -d)"

	log_dim "  fetching the pnpm installer, pnpm $MOD_PIN"
	if ! fetch_to_stdout "https://get.pnpm.io/install.sh" > "$tmp/install.sh"; then
		rm -rf "$tmp"
		return 1
	fi

	# HOME points at a throwaway directory for this one invocation: PNPM_HOME
	# is already explicit, so the installer never needs the real $HOME, and a
	# shell-config file it picks despite SHELL/ENV above lands here instead
	# of in a real profile.
	mkdir -p "$tmp/home"
	# PNPM_VERSION unset is how the installer is asked for the newest
	# release; set to the empty string it is not the same thing.
	set -- HOME="$tmp/home" PNPM_HOME="$pnpm_home" SHELL=/bin/sh ENV="$tmp/shinit"
	[ "$MOD_PIN" = "latest" ] || set -- "$@" PNPM_VERSION="$MOD_PIN"
	env "$@" sh "$tmp/install.sh" >/dev/null 2>&1
	status=$?
	rm -rf "$tmp"
	[ "$status" -eq 0 ] || return 1

	# Written unexpanded so the line stays valid if the home directory moves.
	env_add 'export PNPM_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/devbox/pnpm"'
	env_add 'export PATH="$PNPM_HOME/bin:$PATH"'
	[ -x "$pnpm_home/bin/pnpm" ]
}

dvb_main "$@"
