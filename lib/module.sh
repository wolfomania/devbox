#!/bin/sh
# Prelude and command dispatcher for a module script.
#
# A module is one line in the selection screen and one file on disk. It knows
# how to check for one thing and how to install that one thing, and it can be
# run on its own:
#
#   ./modules/lang/go.sh check      print the installed version, or exit 1
#   ./modules/lang/go.sh install    install it, then exit
#   ./modules/lang/go.sh version    print the version it is pinned to
#
# install.sh runs modules through these same commands, so a test that runs a
# module by hand exercises exactly what a real install does.
#
# A module sources this file first, defines dvb_check and dvb_install, and
# calls dvb_main "$@" last.

set -u

# Modules live two directories below the repository root. install.sh exports
# DVB_ROOT; a standalone run works it out from its own path.
if [ -z "${DVB_ROOT:-}" ]; then
	DVB_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
fi

# shellcheck source=log.sh
. "$DVB_ROOT/lib/log.sh"
# shellcheck source=detect.sh
. "$DVB_ROOT/lib/detect.sh"
# shellcheck source=pkg.sh
. "$DVB_ROOT/lib/pkg.sh"
# shellcheck source=paths.sh
. "$DVB_ROOT/lib/paths.sh"

# install.sh has already detected the machine and exported the answers. A
# standalone run has to find out for itself.
[ -n "${DVB_ARCH:-}" ] || detect_all
paths_refresh

# A tool devbox installed a moment ago is on PATH only through the managed env
# file, and this process has not been through a login shell.
load_env

# Path of this module relative to the repository root, which is how the
# manifest names it.
dvb_module_path() {
	script_path="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")"
	printf '%s\n' "${script_path#"$DVB_ROOT"/}"
}

# Fill MOD_PIN and MOD_PIN_EXTRA from the manifest.
#
# Versions are pinned in the manifest and nowhere else, so a module never
# carries a second copy of a version number that can drift from the catalogue
# the selection screen shows. install.sh passes the pin in the environment; a
# standalone run reads it here.
dvb_load_pin() {
	[ -z "${MOD_PIN:-}" ] || return 0

	[ -n "$DVB_PYTHON" ] || die "python3 is required to read the pinned version from the manifest"
	pins="$("$DVB_PYTHON" "$DVB_ROOT/tui/manifest.py" pins "$(dvb_module_path)")" ||
		die "no manifest entry for $(dvb_module_path)"

	MOD_PIN="$(printf '%s' "$pins" | cut -f1)"
	MOD_PIN_EXTRA="$(printf '%s' "$pins" | cut -f2)"
	export MOD_PIN MOD_PIN_EXTRA
}

dvb_usage() {
	cat <<USAGE
usage: $(basename -- "$0") <command>

  check     print the installed version and exit 0, or exit 1 if it is absent
  install   install this module, then exit
  version   print the version this module is pinned to
USAGE
}

dvb_main() {
	: "${MOD_PIN:=}" "${MOD_PIN_EXTRA:=}"

	case "${1:-}" in
		check) dvb_check ;;
		install)
			dvb_load_pin
			dvb_install
			;;
		version)
			dvb_load_pin
			printf '%s\n' "$MOD_PIN"
			;;
		-h | --help | help)
			dvb_usage
			;;
		"")
			dvb_usage >&2
			return 2
			;;
		*)
			printf 'unknown command: %s\n' "$1" >&2
			dvb_usage >&2
			return 2
			;;
	esac
}
