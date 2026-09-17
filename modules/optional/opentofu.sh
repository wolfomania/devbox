#!/bin/sh
# OpenTofu, the MPL-licensed Terraform fork, from its GitHub release tarball.
# Unpacked under $HOME, so no root and no unzip are needed.
#
# MOD_PIN is "latest", which is what the manifest says, or an exact version.
# The asset carries the version in its name, so the newest release has to be
# looked up before the URL can be written.
#
# OpenTofu publishes an apt repository too, but it needs root, and this module
# has never needed any.
#
#   modules/optional/opentofu.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v tofu >/dev/null 2>&1 || return 1
	tofu version 2>/dev/null | head -1 | awk '{print "tofu", substr($2, 2)}'
}

dvb_install() {
	release="$(mod_release opentofu/opentofu)" || return 1
	asset="tofu_${release}_linux_${DVB_ARCH}.tar.gz"
	url="https://github.com/opentofu/opentofu/releases/download/v${release}/${asset}"

	fetch_bin_from_tar "$url" tofu
}

dvb_main "$@"
