#!/bin/sh
# Supabase CLI from its GitHub release tarball. Supabase explicitly does not
# support installing it as a global npm package, so the release asset is the
# only supported path; it is a bare binary, so no root is needed.
#
#   modules/optional/supabase.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

supabase_asset() {
	printf 'supabase_%s_linux_%s.tar.gz\n' "$MOD_PIN" "$DVB_ARCH"
}

dvb_check() {
	command -v supabase >/dev/null 2>&1 || return 1
	printf 'supabase %s\n' "$(supabase --version 2>/dev/null | tail -1)"
}

dvb_install() {
	asset="$(supabase_asset)"
	url="https://github.com/supabase/cli/releases/download/v${MOD_PIN}/${asset}"
	tmp="$(mktemp -d)"

	log_dim "  fetching $asset"
	if ! fetch_to_file "$url" "$tmp/$asset"; then
		rm -rf "$tmp"
		return 1
	fi

	tar -C "$tmp" -xzf "$tmp/$asset" supabase || {
		rm -rf "$tmp"
		return 1
	}

	env_init
	install -m 0755 "$tmp/supabase" "$DVB_BIN/supabase"
	status=$?
	rm -rf "$tmp"
	[ "$status" -eq 0 ] && [ -x "$DVB_BIN/supabase" ]
}

dvb_main "$@"
