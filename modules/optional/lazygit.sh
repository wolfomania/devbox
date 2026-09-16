#!/bin/sh
# lazygit from its GitHub release tarball. A bare binary, so no root is
# needed.
#
#   modules/optional/lazygit.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

lazygit_arch() {
	case "$DVB_ARCH" in
		amd64) printf 'x86_64\n' ;;
		arm64) printf 'arm64\n' ;;
		*)
			log_err "no lazygit build for architecture $DVB_ARCH"
			return 1
			;;
	esac
}

dvb_check() {
	command -v lazygit >/dev/null 2>&1 || return 1
	version="$(lazygit --version 2>/dev/null | tr ',' '\n' | sed -n 's/^ *version=//p')"
	[ -n "$version" ] || return 1
	printf 'lazygit %s\n' "$version"
}

dvb_install() {
	arch="$(lazygit_arch)" || return 1
	asset="lazygit_${MOD_PIN}_linux_${arch}.tar.gz"
	url="https://github.com/jesseduffield/lazygit/releases/download/v${MOD_PIN}/${asset}"
	tmp="$(mktemp -d)"

	log_dim "  fetching $asset"
	if ! fetch_to_file "$url" "$tmp/$asset"; then
		rm -rf "$tmp"
		return 1
	fi

	tar -C "$tmp" -xzf "$tmp/$asset" lazygit || {
		rm -rf "$tmp"
		return 1
	}

	env_init
	install -m 0755 "$tmp/lazygit" "$DVB_BIN/lazygit"
	status=$?
	rm -rf "$tmp"
	[ "$status" -eq 0 ] && [ -x "$DVB_BIN/lazygit" ]
}

dvb_main "$@"
