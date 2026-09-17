#!/bin/sh
# shfmt, a shell script formatter.
#
# From the GitHub release rather than apt: noble packages 3.8.0 against an
# upstream on 3.14.1. The release is a bare binary, not an archive.
#
#   modules/parts/shfmt.sh check | install
#
# One tool of the Shell extras bundle, modules/optional/shelltools.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v shfmt >/dev/null 2>&1 || return 1
	printf 'shfmt %s\n' "$(shfmt --version 2>/dev/null | sed 's/^v//')"
}

dvb_install() {
	release="$(gh_latest_tag mvdan/sh)" || return 1
	url="https://github.com/mvdan/sh/releases/download/v${release}/shfmt_v${release}_linux_${DVB_ARCH}"

	env_init
	# Downloaded to a temporary file first: a fetch that dies part-way
	# through would otherwise truncate the working binary already on PATH.
	tmp="$(mktemp -d)"
	log_dim "  fetching ${url##*/}"
	if ! fetch_to_file "$url" "$tmp/shfmt"; then
		rm -rf "$tmp"
		return 1
	fi
	install -m 0755 "$tmp/shfmt" "$DVB_BIN/shfmt"
	status=$?
	rm -rf "$tmp"
	[ "$status" -eq 0 ] && [ -x "$DVB_BIN/shfmt" ]
}

dvb_main "$@"
