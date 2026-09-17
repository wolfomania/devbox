#!/bin/sh
# k9s, a terminal UI for Kubernetes clusters, from its GitHub release tarball.
# A bare binary, so no root is needed.
#
# It reads the same kubeconfig kubectl does and talks to the cluster itself,
# so it works whether or not the kubectl module is installed.
#
# MOD_PIN is "latest", which is what the manifest says, or an exact version.
# The asset is named without the version in it, so the newest release can be
# fetched through the /releases/latest/ redirect. The platform in that name is
# capitalised, unlike every other project here.
#
#   modules/optional/k9s.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v k9s >/dev/null 2>&1 || return 1
	# `k9s version` draws an ASCII-art banner; --short is the one that does
	# not, and prints "Version<tab>v0.51.0".
	version="$(k9s version --short 2>/dev/null | awk '/^Version/ {sub(/^v/, "", $2); print $2; exit}')"
	[ -n "$version" ] || return 1
	printf 'k9s %s\n' "$version"
}

dvb_install() {
	asset="k9s_Linux_${DVB_ARCH}.tar.gz"
	if [ "$MOD_PIN" = "latest" ]; then
		url="https://github.com/derailed/k9s/releases/latest/download/${asset}"
	else
		url="https://github.com/derailed/k9s/releases/download/v${MOD_PIN}/${asset}"
	fi

	fetch_bin_from_tar "$url" k9s
}

dvb_main "$@"
