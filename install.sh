#!/bin/sh
# devbox - one command to provision a development box.
#
#   curl -fsSL https://raw.githubusercontent.com/wolfomania/devbox/main/install.sh | sudo sh
#   ./install.sh                     interactive
#   ./install.sh --list              show what is installed and what is missing
#   ./install.sh --yes               install the default selection, no prompts
#   ./install.sh --profile work.conf --yes
#
# Detection never changes the machine. The only things written before the
# install phase are temporary files under $TMPDIR.

set -u

DVB_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
export DVB_ROOT

# HOME is not guaranteed. A command sent over SSM, a cron job and a systemd
# unit all arrive without one, and `set -u` would end the script on the first
# path it builds. This is the same job lib/paths.sh does in paths_ensure_home,
# written out again because piped into a shell there are no libraries yet and
# the download path below already needs a home directory.
if [ -z "${HOME:-}" ]; then
	HOME="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)"
	if [ -z "$HOME" ] && [ "$(id -u)" -eq 0 ]; then
		HOME=/root
	fi
	[ -n "$HOME" ] || {
		printf 'devbox: HOME is unset and uid %s has no home directory\n' "$(id -u)" >&2
		exit 1
	}
	export HOME
fi

# --- bootstrap -------------------------------------------------------------
#
# Piped into a shell there is no repository on disk, only this file. Fetch the
# rest, then hand over to the copy that has its libraries next to it.

DVB_REPO="${DVB_REPO:-wolfomania/devbox}"
DVB_REF="${DVB_REF:-main}"
DVB_SRC="${XDG_DATA_HOME:-$HOME/.local/share}/devbox/src"

boot_fetch() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO- "$1"
	else
		echo "devbox: curl or wget is required" >&2
		return 1
	fi
}

boot_download() {
	command -v tar >/dev/null 2>&1 || {
		echo "devbox: tar is required" >&2
		return 1
	}

	echo "devbox: fetching $DVB_REPO@$DVB_REF"
	rm -rf "$DVB_SRC"
	mkdir -p "$DVB_SRC" || return 1
	boot_fetch "https://codeload.github.com/$DVB_REPO/tar.gz/refs/heads/$DVB_REF" |
		tar -xz -C "$DVB_SRC" --strip-components=1 || return 1
	[ -r "$DVB_SRC/lib/detect.sh" ] || {
		echo "devbox: download looks incomplete" >&2
		return 1
	}
}

# Re-exec from the downloaded copy. stdin is the script itself when piped, so
# reattach the terminal or the selection screen has nothing to read.
boot_handover() {
	chmod +x "$DVB_SRC/install.sh" 2>/dev/null
	# A readable /dev/tty node is not enough: a process with no controlling
	# terminal can see the node and still fail to open it. Try it in a subshell.
	if [ ! -t 0 ] && (exec 3< /dev/tty) 2>/dev/null; then
		exec sh "$DVB_SRC/install.sh" "$@" < /dev/tty
	fi
	exec sh "$DVB_SRC/install.sh" "$@"
}

if [ ! -r "$DVB_ROOT/lib/detect.sh" ]; then
	boot_download || exit 1
	boot_handover "$@"
fi

# The catalogue is a directory of *.toml files, read in filename order. A
# single manifest.toml is still accepted, for a fork that prefers one file.
if [ -z "${DVB_MANIFEST:-}" ]; then
	if [ -d "$DVB_ROOT/manifests" ]; then
		DVB_MANIFEST="$DVB_ROOT/manifests"
	else
		DVB_MANIFEST="$DVB_ROOT/manifest.toml"
	fi
fi
export DVB_MANIFEST

# shellcheck source=lib/log.sh
. "$DVB_ROOT/lib/log.sh"
# shellcheck source=lib/detect.sh
. "$DVB_ROOT/lib/detect.sh"
# shellcheck source=lib/pkg.sh
. "$DVB_ROOT/lib/pkg.sh"
# shellcheck source=lib/swap.sh
. "$DVB_ROOT/lib/swap.sh"
# shellcheck source=lib/paths.sh
. "$DVB_ROOT/lib/paths.sh"

OPT_YES=0
OPT_LIST=0
OPT_DRY_RUN=0
OPT_PROFILE=""
OPT_SAVE_PROFILE=""
OPT_WITH=""
OPT_WITHOUT=""

usage() {
	cat <<'USAGE'
usage: install.sh [options]

  -y, --yes               install without opening the selection screen
      --list              print module status and exit, changing nothing
      --profile FILE      read the selection from a profile file
      --save-profile FILE write the selection to a profile file
      --with a,b,c        add modules to the selection
      --without a,b,c     remove modules from the selection
      --dry-run           show what would be installed, install nothing
  -h, --help              this message

With no options the selection screen opens. Arrow keys move, space toggles,
enter installs, q quits.
USAGE
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
			-y | --yes) OPT_YES=1 ;;
			--list) OPT_LIST=1 ;;
			--dry-run) OPT_DRY_RUN=1 ;;
			--profile)
				OPT_PROFILE="${2:-}"
				shift
				;;
			--save-profile)
				OPT_SAVE_PROFILE="${2:-}"
				shift
				;;
			--with)
				OPT_WITH="${2:-}"
				shift
				;;
			--without)
				OPT_WITHOUT="${2:-}"
				shift
				;;
			-h | --help)
				usage
				exit 0
				;;
			*) die "unknown option: $1  (try --help)" ;;
		esac
		shift
	done
}

# --- the account being provisioned -----------------------------------------

# Under `| sudo sh` everything runs as root, so HOME is /root and every
# per-user tool would land there, invisible to the person who asked for it.
# Point HOME at the invoking account instead. env_hand_back returns ownership
# once the install is done.
#
# Only root may do this. SUDO_USER is inherited like any other variable, and a
# chain such as `sudo -iu ubuntu` leaves the previous account's name in it:
# ubuntu would then install into /home/ssm-user, which it cannot write, and
# every module would fail on Permission denied.
adopt_invoking_user() {
	DVB_USER="$(id -un)"
	[ "$(id -u)" -eq 0 ] || return 0
	[ -n "${SUDO_USER:-}" ] || return 0
	[ "$SUDO_USER" != "root" ] || return 0

	user_home="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)"
	[ -n "$user_home" ] && [ -d "$user_home" ] || return 0

	DVB_USER="$SUDO_USER"
	HOME="$user_home"
	export HOME
	paths_refresh
	detect_disk
}

# Root created these on someone else's behalf; hand them over.
env_hand_back() {
	[ "$(id -u)" -eq 0 ] || return 0
	[ -n "${DVB_USER:-}" ] && [ "$DVB_USER" != "root" ] || return 0

	for path in "$DVB_ENV_DIR" "$DVB_BIN" "$DVB_PREFIX" \
		"$HOME/.nvm" "$HOME/.cargo" "$HOME/.rustup" "$HOME/.local"; do
		[ -e "$path" ] || continue
		chown -R "$DVB_USER" "$path" 2>/dev/null || true
	done
}

# --- python ----------------------------------------------------------------

require_python() {
	detect_python
	[ -n "$DVB_PYTHON" ] && return 0

	if [ "$DVB_CAN_ROOT" -eq 1 ] && pkg_supported; then
		log_warn "python3 is missing; installing it first"
		pkg_install python3 || die "could not install python3"
		detect_python
	fi

	[ -n "$DVB_PYTHON" ] || die "python3 with the curses module is required and could not be installed"
}

manifest_query() {
	"$DVB_PYTHON" "$DVB_ROOT/tui/manifest.py" "$@"
}

# --- probing ---------------------------------------------------------------

# Ask one module whether its tool is already there. Modules are run, not
# sourced, so a module's helpers and variables can never leak into this script
# or into the next module.
probe_one() {
	# stdin here is the pipe probe_all is reading the module list from, and a
	# check that read a line of it would silently eat the next module.
	"$DVB_ROOT/$1" check < /dev/null 2>/dev/null
}

# Writes "id<TAB>status<TAB>version" for every module in the manifest.
probe_all() {
	out_file="$1"
	: > "$out_file"

	manifest_query rows | while IFS="$(printf '\t')" read -r id script needs_root pin pin_extra name; do
		[ -n "$id" ] || continue
		if version="$(probe_one "$script")" && [ -n "$version" ]; then
			printf '%s\t%s\t%s\n' "$id" "installed" "$version" >> "$out_file"
		else
			printf '%s\t%s\t%s\n' "$id" "missing" "" >> "$out_file"
		fi
	done
}

state_of() {
	awk -F'\t' -v want="$1" '$1 == want {print $2}' "$STATE_FILE"
}

version_of() {
	awk -F'\t' -v want="$1" '$1 == want {print $3}' "$STATE_FILE"
}

print_list() {
	log_head "Modules"
	manifest_query rows | while IFS="$(printf '\t')" read -r id script needs_root pin pin_extra name; do
		status="$(state_of "$id")"
		version="$(version_of "$id")"
		if [ "$status" = "installed" ]; then
			printf '  %s%-4s%s %-18s %s\n' "$C_GREEN" "ok" "$C_RESET" "$id" "$version"
		elif [ "$needs_root" = "1" ] && [ "$DVB_CAN_ROOT" -eq 0 ]; then
			printf '  %s%-4s%s %-18s needs root\n' "$C_YELLOW" "--" "$C_RESET" "$id"
		else
			printf '  %s%-4s%s %-18s not installed, pinned %s\n' "$C_DIM" "--" "$C_RESET" "$id" "$pin"
		fi
	done
}

# --- selection -------------------------------------------------------------

read_profile() {
	[ -r "$1" ] || die "profile not found: $1"
	grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$' | tr -d ' \t'
}

# Strip anything already installed or blocked by missing root, then order by
# dependency. Prints the final id list.
filter_selection() {
	while read -r id; do
		[ -n "$id" ] || continue
		[ "$(state_of "$id")" = "installed" ] && continue
		needs_root="$(manifest_query field "$id" needs_root)"
		if [ "$needs_root" = "True" ] && [ "$DVB_CAN_ROOT" -eq 0 ]; then
			log_skip "$id needs root"
			continue
		fi
		printf '%s\n' "$id"
	done
}

apply_with_without() {
	base_list="$1"
	if [ -n "$OPT_WITH" ]; then
		extra="$(printf '%s' "$OPT_WITH" | tr ',' '\n')"
		base_list="$(printf '%s\n%s\n' "$base_list" "$extra")"
	fi
	if [ -n "$OPT_WITHOUT" ]; then
		for drop in $(printf '%s' "$OPT_WITHOUT" | tr ',' ' '); do
			base_list="$(printf '%s\n' "$base_list" | grep -vx "$drop")"
		done
	fi
	printf '%s\n' "$base_list" | grep -v '^$' | sort -u
}

select_headless() {
	if [ -n "$OPT_PROFILE" ]; then
		raw="$(read_profile "$OPT_PROFILE")"
	else
		raw="$(manifest_query defaults)"
	fi
	apply_with_without "$raw" | filter_selection > "$SELECT_FILE"
	reorder_selection
}

select_interactive() {
	machine="$DVB_OS_NAME $(printf '\302\267') $DVB_ARCH $(printf '\302\267') ${DVB_RAM_MB} MiB ram"
	case "$DVB_PRIV" in
		none) machine="$machine $(printf '\302\267') no root" ;;
		*) machine="$machine $(printf '\302\267') root ok" ;;
	esac

	"$DVB_PYTHON" "$DVB_ROOT/tui/app.py" \
		--manifest "$DVB_MANIFEST" \
		--state "$STATE_FILE" \
		--out "$SELECT_FILE" \
		--machine "$machine" \
		--can-root "$DVB_CAN_ROOT"
}

reorder_selection() {
	[ -s "$SELECT_FILE" ] || return 0
	ids="$(tr '\n' ' ' < "$SELECT_FILE")"
	# shellcheck disable=SC2086
	manifest_query order $ids > "$SELECT_FILE.ordered"
	mv "$SELECT_FILE.ordered" "$SELECT_FILE"
}

# --- installing ------------------------------------------------------------

install_one() {
	id="$1"
	row="$(manifest_query rows | awk -F'\t' -v want="$id" '$1 == want')"
	script="$(printf '%s' "$row" | cut -f2)"
	name="$(printf '%s' "$row" | cut -f6)"
	pin="$(printf '%s' "$row" | cut -f4)"
	pin_extra="$(printf '%s' "$row" | cut -f5)"

	log_step "$name"
	if [ "$OPT_DRY_RUN" -eq 1 ]; then
		log_skip "dry run, not installing $id"
		return 0
	fi

	# The pin comes from the manifest row read above. A module run by hand
	# with no MOD_PIN looks it up in the manifest itself.
	# Same reason as in probe_one: stdin is the selection file this loop is
	# reading. sudo still gets its password prompt, which it takes from the
	# terminal rather than from stdin.
	if MOD_PIN="$pin" MOD_PIN_EXTRA="$pin_extra" "$DVB_ROOT/$script" install < /dev/null; then
		version="$(probe_one "$script" || true)"
		log_ok "${name}${version:+ - $version}"
		return 0
	fi

	log_err "$name failed"
	return 1
}

install_selection() {
	failed=""
	installed=0

	while read -r id; do
		[ -n "$id" ] || continue
		if install_one "$id"; then
			installed=$((installed + 1))
		else
			failed="$failed $id"
		fi
	done < "$SELECT_FILE"

	if [ "$OPT_DRY_RUN" -eq 1 ]; then
		log_head "Dry run"
		printf '  %d module(s) would be installed; nothing was changed\n' "$installed"
		return 0
	fi

	env_link_profiles
	env_hand_back

	log_head "Done"
	printf '  %d module(s) installed\n' "$installed"
	if [ -n "$failed" ]; then
		log_warn "failed:$failed"
		return 1
	fi
	log_dim "  open a new shell, or run:  . $DVB_ENV_FILE"
}

# --- low memory ------------------------------------------------------------

offer_swap() {
	swap_is_low || return 0

	log_warn "only ${DVB_RAM_MB} MiB of ram and ${DVB_SWAP_MB} MiB of swap; large toolchains may fail"
	if ! swap_can_create; then
		log_dim "  cannot add swap here (needs root, free disk and no existing /swapfile)"
		return 0
	fi
	if [ "$OPT_YES" -eq 1 ]; then
		log_dim "  --yes given; not creating swap without being asked"
		return 0
	fi

	printf '  Create a %s MiB swapfile at %s? [y/N] ' "$SWAP_CREATE_MB" "$SWAP_PATH"
	read -r answer
	case "$answer" in
		y | Y | yes | YES) swap_create || log_warn "swapfile creation failed, continuing" ;;
		*) log_skip "no swapfile created" ;;
	esac
}

report_capabilities() {
	[ "$DVB_CAN_ROOT" -eq 1 ] && return 0

	log_warn "not running as root and sudo is unavailable"
	printf '  These modules cannot be set up and will be shown as unavailable:\n'
	manifest_query rows | awk -F'\t' '$3 == "1" {printf "    %s (%s)\n", $1, $6}'
	printf '  Everything else installs under %s and needs no root.\n' "$HOME"
	printf '  Re-run with sudo to enable the rest.\n'
}

# --- main ------------------------------------------------------------------

probe_report() {
	log_step "Checking what is already installed"
	probe_all "$STATE_FILE"
	installed_count="$(awk -F'\t' '$2 == "installed"' "$STATE_FILE" | wc -l | tr -d ' ')"
	total_count="$(wc -l < "$STATE_FILE" | tr -d ' ')"
	log_dim "  $installed_count of $total_count modules already present"
}

run_selection() {
	if [ -n "$OPT_SAVE_PROFILE" ]; then
		cp "$SELECT_FILE" "$OPT_SAVE_PROFILE"
		log_ok "selection saved to $OPT_SAVE_PROFILE"
	fi

	log_head "Installing"
	# Print the name the selection screen showed, not the internal id.
	while read -r id; do
		[ -n "$id" ] || continue
		printf '  %s\n' "$(manifest_query field "$id" name)"
	done < "$SELECT_FILE"

	if [ "$OPT_DRY_RUN" -eq 0 ]; then
		offer_swap
		env_init
	fi
	install_selection
}

# Wait for the user before painting over the install log with the menu again.
pause_for_menu() {
	printf '\n%s  press enter for the selection screen, q to quit: %s' "$C_DIM" "$C_RESET"
	read -r answer || return 1
	case "$answer" in
		q | Q | quit | exit) return 1 ;;
	esac
	return 0
}

# The selection screen is the home base. It opens, hands control to the
# installer, and comes back with refreshed state when that finishes, however
# that went. Only q or escape leaves.
interactive_loop() {
	while true; do
		probe_report
		select_interactive
		case $? in
			0) ;;
			2)
				log_head "Nothing installed"
				return 0
				;;
			*) die "the selection screen failed" ;;
		esac

		if [ -s "$SELECT_FILE" ]; then
			run_selection || true
		else
			log_head "Nothing to do"
			log_dim "  everything ticked is already installed"
		fi

		pause_for_menu || return 0
	done
}

main() {
	parse_args "$@"

	detect_all
	adopt_invoking_user
	require_python
	detect_export
	detect_report
	if [ "$DVB_USER" != "$(id -un)" ]; then
		printf '  %-12s %s (%s)\n' "installing for" "$DVB_USER" "$HOME"
	fi
	report_capabilities

	tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/devbox.XXXXXX")"
	trap 'rm -rf "$tmp_dir"' EXIT INT TERM
	# Modules are separate processes; this is where they leave the per-run
	# notes they need to share, such as "the apt index is already refreshed".
	DVB_RUN_DIR="$tmp_dir"
	export DVB_RUN_DIR
	STATE_FILE="$tmp_dir/state.tsv"
	SELECT_FILE="$tmp_dir/select.txt"

	if [ "$OPT_LIST" -eq 1 ]; then
		probe_report
		print_list
		exit 0
	fi

	if [ "$OPT_YES" -eq 1 ] || [ -n "$OPT_PROFILE" ] || [ ! -t 0 ]; then
		probe_report
		select_headless
		if [ ! -s "$SELECT_FILE" ]; then
			log_head "Nothing to do"
			log_dim "  everything selected is already installed"
			exit 0
		fi
		run_selection
		exit $?
	fi

	interactive_loop
}

main "$@"
