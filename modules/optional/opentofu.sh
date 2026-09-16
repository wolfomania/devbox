#!/bin/sh
# OpenTofu, the MPL-licensed Terraform fork, from its pinned GitHub release
# tarball. Unpacked under $HOME, so no root and no unzip are needed.
#
#   modules/optional/opentofu.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v tofu >/dev/null 2>&1 || return 1
	tofu version 2>/dev/null | head -1 | awk '{print "tofu", substr($2, 2)}'
}

dvb_install() {
	env_init
	tarball="tofu_${MOD_PIN}_linux_${DVB_ARCH}.tar.gz"
	tmp="$(mktemp -d)"

	log_dim "  fetching $tarball"
	if ! fetch_to_file "https://github.com/opentofu/opentofu/releases/download/v${MOD_PIN}/${tarball}" "$tmp/$tarball"; then
		rm -rf "$tmp"
		return 1
	fi

	tar -C "$tmp" -xzf "$tmp/$tarball" tofu || {
		rm -rf "$tmp"
		return 1
	}

	install -m 0755 "$tmp/tofu" "$DVB_PREFIX/tofu" || {
		rm -rf "$tmp"
		return 1
	}
	rm -rf "$tmp"

	env_link_bin "$DVB_PREFIX/tofu"
	[ -x "$DVB_BIN/tofu" ]
}

dvb_main "$@"
