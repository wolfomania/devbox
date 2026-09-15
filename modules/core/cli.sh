#!/bin/sh
# The shell utilities assumed by the rest of this setup.

CLI_PACKAGES="ripgrep jq fzf tmux htop tree"

dvb_check() {
	found=0
	total=0
	for tool in rg jq fzf tmux htop tree; do
		total=$((total + 1))
		command -v "$tool" >/dev/null 2>&1 && found=$((found + 1))
	done
	[ "$found" -eq "$total" ] || return 1
	printf '%s of %s present\n' "$found" "$total"
}

dvb_install() {
	# shellcheck disable=SC2086
	pkg_install $CLI_PACKAGES
}
