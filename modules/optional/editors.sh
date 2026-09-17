#!/bin/sh
# Neovim from its own GitHub release, with no configuration imposed;
# ~/.config/nvim is left untouched.
#
# Not from apt: noble packages 0.9.5, frozen in 2023, against an upstream on
# 0.12. Three years of Lua API, LSP and Treesitter work sit in that gap, and
# a configuration written against a current Neovim will not load on 0.9.
#
# Not from the snap either, though the Neovim project publishes one. snapd
# needs systemd and, in practice, a privileged container, so a snap module
# could not be tested by ./tests/modules/run.sh at all.
#
# MOD_PIN is "latest", which is what the manifest says, or an exact version.
# The asset is named without the version in it, so the newest release comes
# through the /releases/latest/ redirect.
#
# The release is a tree, not a single binary, so it is unpacked under
# ~/.local/share/devbox and only nvim itself is linked onto PATH.
#
#   modules/optional/editors.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

nvim_asset() {
	case "$DVB_ARCH" in
		amd64) printf 'nvim-linux-x86_64.tar.gz\n' ;;
		arm64) printf 'nvim-linux-arm64.tar.gz\n' ;;
		*)
			log_err "no Neovim build for architecture $DVB_ARCH"
			return 1
			;;
	esac
}

dvb_check() {
	command -v nvim >/dev/null 2>&1 || return 1
	nvim --version 2>/dev/null | head -1 | awk '{print "nvim", substr($2, 2)}'
}

dvb_install() {
	asset="$(nvim_asset)" || return 1
	if [ "$MOD_PIN" = "latest" ]; then
		url="https://github.com/neovim/neovim/releases/latest/download/${asset}"
	else
		url="https://github.com/neovim/neovim/releases/download/v${MOD_PIN}/${asset}"
	fi

	env_init
	tmp="$(mktemp -d)"
	log_dim "  fetching $asset"
	if ! fetch_to_file "$url" "$tmp/$asset"; then
		rm -rf "$tmp"
		return 1
	fi

	# Unpacked into a directory of its own, so an upgrade replaces the whole
	# tree rather than leaving a previous release's runtime files mixed in.
	rm -rf "$DVB_PREFIX/nvim"
	mkdir -p "$DVB_PREFIX/nvim"
	if ! tar -C "$DVB_PREFIX/nvim" --strip-components=1 -xzf "$tmp/$asset"; then
		rm -rf "$tmp"
		return 1
	fi
	rm -rf "$tmp"

	env_link_bin "$DVB_PREFIX/nvim/bin/nvim"
	[ -x "$DVB_BIN/nvim" ]
}

dvb_main "$@"
