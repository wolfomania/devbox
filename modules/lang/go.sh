#!/bin/sh
# Go from the official tarball, unpacked under $HOME rather than /usr/local,
# so the module needs no root.
#
# MOD_PIN is either "latest", which is what the manifest says, or an exact
# version to hold at. Go publishes its newest release as one line of plain
# text at go.dev/VERSION, which is the only way to ask for the newest one:
# the download URLs all name a version, and there is no redirect that fills
# it in.
#
#   modules/lang/go.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v go >/dev/null 2>&1 || return 1
	go version 2>/dev/null | awk '{print "go", substr($3, 3)}'
}

# "go1.27.1", whether that came from the manifest or from go.dev.
go_release() {
	if [ "$MOD_PIN" != "latest" ]; then
		printf 'go%s\n' "$MOD_PIN"
		return 0
	fi

	release="$(fetch_to_stdout "https://go.dev/VERSION?m=text" | head -1)"
	case "$release" in
		go[0-9]*) printf '%s\n' "$release" ;;
		*)
			log_err "go.dev/VERSION did not answer with a version"
			return 1
			;;
	esac
}

dvb_install() {
	env_init
	release="$(go_release)" || return 1
	tarball="${release}.linux-${DVB_ARCH}.tar.gz"
	tmp="$(mktemp -d)"

	log_dim "  fetching $tarball"
	if ! fetch_to_file "https://go.dev/dl/${tarball}" "$tmp/$tarball"; then
		rm -rf "$tmp"
		return 1
	fi

	rm -rf "$DVB_PREFIX/go"
	tar -C "$DVB_PREFIX" -xzf "$tmp/$tarball" || {
		rm -rf "$tmp"
		return 1
	}
	rm -rf "$tmp"

	env_link_bin "$DVB_PREFIX/go/bin/go"
	env_link_bin "$DVB_PREFIX/go/bin/gofmt"
	# Written unexpanded so the line stays valid if the home directory moves.
	env_add 'export PATH="${XDG_DATA_HOME:-$HOME/.local/share}/devbox/go/bin:$PATH"'
	env_add 'export PATH="$HOME/go/bin:$PATH"'
	[ -x "$DVB_PREFIX/go/bin/go" ]
}

dvb_main "$@"
