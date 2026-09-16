#!/bin/sh
# Helm from the canonical tarball at get.helm.sh, which is what Helm's own
# install script uses. Unpacked under $HOME, so no root is needed.
#
#   modules/optional/helm.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v helm >/dev/null 2>&1 || return 1
	helm version --short 2>/dev/null | awk '{sub(/^v/, "", $1); sub(/\+.*/, "", $1); print "helm", $1}'
}

dvb_install() {
	env_init
	tarball="helm-v${MOD_PIN}-linux-${DVB_ARCH}.tar.gz"
	tmp="$(mktemp -d)"

	log_dim "  fetching $tarball"
	if ! fetch_to_file "https://get.helm.sh/${tarball}" "$tmp/$tarball"; then
		rm -rf "$tmp"
		return 1
	fi

	tar -C "$tmp" -xzf "$tmp/$tarball" || {
		rm -rf "$tmp"
		return 1
	}

	install -m 0755 "$tmp/linux-${DVB_ARCH}/helm" "$DVB_PREFIX/helm" || {
		rm -rf "$tmp"
		return 1
	}
	rm -rf "$tmp"

	env_link_bin "$DVB_PREFIX/helm"
	[ -x "$DVB_BIN/helm" ]
}

dvb_main "$@"
