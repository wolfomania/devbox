#!/bin/sh
# Go from the official tarball, unpacked under $HOME rather than /usr/local,
# so the module needs no root.

dvb_check() {
	command -v go >/dev/null 2>&1 || return 1
	go version 2>/dev/null | awk '{print "go", substr($3, 3)}'
}

dvb_install() {
	env_init
	tarball="go${MOD_PIN}.linux-${DVB_ARCH}.tar.gz"
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
