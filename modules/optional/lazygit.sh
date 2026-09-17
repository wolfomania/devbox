#!/bin/sh
# lazygit from its GitHub release tarball. A bare binary, so no root is
# needed.
#
# MOD_PIN is "latest", which is what the manifest says, or an exact version.
# The asset carries the version in its name, so the newest release has to be
# looked up before the URL can be written.
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
	release="$(mod_release jesseduffield/lazygit)" || return 1
	asset="lazygit_${release}_linux_${arch}.tar.gz"
	url="https://github.com/jesseduffield/lazygit/releases/download/v${release}/${asset}"

	fetch_bin_from_tar "$url" lazygit
}

dvb_main "$@"
