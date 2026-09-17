#!/bin/sh
# fzf, the interactive fuzzy finder.
#
# From the GitHub release rather than apt: noble packages 0.44, from 2023,
# against an upstream on 0.74, and the gap covers most of what people reach
# for fzf to do.
#
#   modules/parts/fzf.sh check | install
#
# One tool of the Shell toolkit bundle, modules/core/cli.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v fzf >/dev/null 2>&1 || return 1
	printf 'fzf %s\n' "$(fzf --version 2>/dev/null | awk '{print $1}')"
}

dvb_install() {
	release="$(gh_latest_tag junegunn/fzf)" || return 1
	asset="fzf-${release}-linux_${DVB_ARCH}.tar.gz"
	url="https://github.com/junegunn/fzf/releases/download/v${release}/${asset}"

	fetch_bin_from_tar "$url" fzf
}

dvb_main "$@"
