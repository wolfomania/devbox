#!/bin/sh
# mikefarah's yq: a single Go binary for YAML, JSON and XML, not the
# unrelated Python "yq" wrapper around jq. Fetched straight from the GitHub
# release, so no root is needed.
#
# MOD_PIN is "latest", which is what the manifest says, or an exact version.
# yq names its asset without the version in it, so the newest release can be
# fetched through the /releases/latest/ redirect without asking the API which
# one that is.
#
#   modules/optional/yq.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v yq >/dev/null 2>&1 || return 1
	version="$(yq --version 2>/dev/null | awk '{sub(/^v/, "", $NF); print $NF}')"
	[ -n "$version" ] || return 1
	printf 'yq %s\n' "$version"
}

dvb_install() {
	asset="yq_linux_${DVB_ARCH}"
	if [ "$MOD_PIN" = "latest" ]; then
		url="https://github.com/mikefarah/yq/releases/latest/download/${asset}"
	else
		url="https://github.com/mikefarah/yq/releases/download/v${MOD_PIN}/${asset}"
	fi
	env_init

	# Downloaded to a temporary file first: a fetch that dies part-way through
	# would otherwise truncate the working binary already on PATH, leaving a
	# yq that runs but prints no version.
	tmp="$(mktemp -d)"
	log_dim "  fetching $asset"
	if ! fetch_to_file "$url" "$tmp/yq"; then
		rm -rf "$tmp"
		return 1
	fi

	install -m 0755 "$tmp/yq" "$DVB_BIN/yq"
	status=$?
	rm -rf "$tmp"
	[ "$status" -eq 0 ] && [ -x "$DVB_BIN/yq" ]
}

dvb_main "$@"
