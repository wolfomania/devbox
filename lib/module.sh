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
#
# A module whose menu line covers several independently useful tools is a
# bundle: its parts live in modules/parts, one tool each, and the bundle calls
# dvb_check_parts and dvb_install_parts. A part is a module in every other
# respect, and can be run on its own the same way. It sets DVB_UNLISTED=1
# before sourcing this file, because it has no line of its own in the manifest
# and so no pinned version to look up.

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

# Where processes in one run leave notes for each other, such as "the apt index
# is already refreshed". install.sh provides one. A module run on its own makes
# its own, so that a bundle installing six parts still refreshes apt once
# rather than once per part.
if [ -z "${DVB_RUN_DIR:-}" ]; then
	DVB_RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devbox-run.XXXXXX")"
	export DVB_RUN_DIR
	# Interrupted, the trap must leave as well as clean up; see install.sh.
	trap 'rm -rf "$DVB_RUN_DIR"' EXIT
	trap 'rm -rf "$DVB_RUN_DIR"; exit 130' INT
	trap 'rm -rf "$DVB_RUN_DIR"; exit 143' TERM
fi

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
	[ "${DVB_UNLISTED:-0}" -eq 0 ] || return 0

	[ -n "$DVB_PYTHON" ] || die "python3 is required to read the pinned version from the manifest"
	pins="$("$DVB_PYTHON" "$DVB_ROOT/tui/manifest.py" pins "$(dvb_module_path)")" ||
		die "no manifest entry for $(dvb_module_path)"

	MOD_PIN="$(printf '%s' "$pins" | cut -f1)"
	MOD_PIN_EXTRA="$(printf '%s' "$pins" | cut -f2)"
	export MOD_PIN MOD_PIN_EXTRA
}

# The release this module should install: the version the manifest pins, or
# the newest release of a GitHub repository when the pin says "latest".
#
# Everything here that is not a language runtime takes the latest release,
# and most of those live on GitHub. A module that can name its asset without
# the version -- yq and supabase both can, through the /releases/latest/
# download/ redirect -- does not need this and does not call it.
mod_release() {
	if [ "$MOD_PIN" = "latest" ]; then
		gh_latest_tag "$1"
	else
		printf '%s\n' "$MOD_PIN"
	fi
}

# --- bundles ---------------------------------------------------------------

dvb_part() { printf '%s\n' "$DVB_ROOT/modules/parts/$1.sh"; }

# Install each part in turn.
#
# Every part is attempted even after one fails, because the tools in a bundle
# do not depend on each other and a box with five of the six is more useful
# than a box with none. The names that failed are reported together.
dvb_install_parts() {
	failed=""
	for part in "$@"; do
		"$(dvb_part "$part")" install || failed="$failed $part"
	done

	[ -z "$failed" ] || {
		log_err "part(s) failed:$failed"
		return 1
	}
	return 0
}

# A bundle is installed when every one of its parts is.
#
# The count is printed either way, so a bundle that is half there says so
# rather than reading as entirely absent.
dvb_check_parts() {
	present=0
	total=0
	for part in "$@"; do
		total=$((total + 1))
		"$(dvb_part "$part")" check > /dev/null 2>&1 && present=$((present + 1))
	done

	printf '%d of %d present\n' "$present" "$total"
	[ "$present" -eq "$total" ]
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
			[ "${DVB_UNLISTED:-0}" -eq 0 ] ||
				die "no pinned version: this script is one part of a bundle"
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
