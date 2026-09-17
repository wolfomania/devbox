#!/bin/sh
# Supabase CLI from its GitHub release tarball. Supabase explicitly does not
# support installing it as a global npm package, so the release asset is the
# only supported path; it is a bare binary, so no root is needed.
#
# MOD_PIN is "latest", which is what the manifest says, or an exact version.
# The tarball is named without the version in it, so the newest release can be
# fetched through the /releases/latest/ redirect. Supabase also publishes a
# .deb now, but that one does carry the version in its name and so cannot be.
#
#   modules/optional/supabase.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v supabase >/dev/null 2>&1 || return 1
	printf 'supabase %s\n' "$(supabase --version 2>/dev/null | tail -1)"
}

dvb_install() {
	asset="supabase_linux_${DVB_ARCH}.tar.gz"
	if [ "$MOD_PIN" = "latest" ]; then
		url="https://github.com/supabase/cli/releases/latest/download/${asset}"
	else
		url="https://github.com/supabase/cli/releases/download/v${MOD_PIN}/supabase_${MOD_PIN}_linux_${DVB_ARCH}.tar.gz"
	fi

	fetch_bin_from_tar "$url" supabase
}

dvb_main "$@"
