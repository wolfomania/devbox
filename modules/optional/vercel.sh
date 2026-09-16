#!/bin/sh
# Vercel CLI from npm, pinned to an exact version. Depends on the Node
# module, which the runner installs first.
#
#   modules/optional/vercel.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v vercel >/dev/null 2>&1 || return 1
	printf 'vercel %s\n' "$(vercel --version 2>/dev/null | awk '{print $NF}')"
}

dvb_install() {
	if ! command -v npm >/dev/null 2>&1; then
		# The node module is installed in the same run, so pick it up from
		# the managed env rather than relying on a shell restart.
		[ -f "$DVB_ENV_FILE" ] && . "$DVB_ENV_FILE"
	fi

	command -v npm >/dev/null 2>&1 || {
		log_err "npm not found; the Node module must be installed first"
		return 1
	}

	log_dim "  npm install -g vercel@$MOD_PIN"
	npm install -g "vercel@$MOD_PIN" >/dev/null 2>&1
}

dvb_main "$@"
