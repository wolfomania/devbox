#!/bin/sh
# devbox - one command to provision a development box.
#
#   ./install.sh                     interactive
#   ./install.sh --list              show what is installed and what is missing
#   ./install.sh --yes               install the default selection, no prompts
#   ./install.sh --profile work.conf --yes
#
# Detection never changes the machine. The only things written before the
# install phase are temporary files under $TMPDIR.

set -u

DVB_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
DVB_MANIFEST="${DVB_MANIFEST:-$DVB_ROOT/manifest.toml}"
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

# Run one module's check in a subshell so module functions never collide.
probe_one() {
	probe_script="$1"
	(
		load_env
		# shellcheck source=/dev/null
		. "$DVB_ROOT/$probe_script"
		dvb_check
	) 2>/dev/null
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
		--can-root "$DVB_CAN_ROOT" || return 1
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

	if (
		load_env
		MOD_PIN="$pin"
		MOD_PIN_EXTRA="$pin_extra"
		export MOD_PIN MOD_PIN_EXTRA
		# shellcheck source=/dev/null
		. "$DVB_ROOT/$script"
		dvb_install
	); then
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

main() {
	parse_args "$@"

	detect_all
	require_python
	detect_report
	report_capabilities

	tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/devbox.XXXXXX")"
	trap 'rm -rf "$tmp_dir"' EXIT INT TERM
	STATE_FILE="$tmp_dir/state.tsv"
	SELECT_FILE="$tmp_dir/select.txt"

	log_step "Checking what is already installed"
	probe_all "$STATE_FILE"
	installed_count="$(awk -F'\t' '$2 == "installed"' "$STATE_FILE" | wc -l | tr -d ' ')"
	total_count="$(wc -l < "$STATE_FILE" | tr -d ' ')"
	log_dim "  $installed_count of $total_count modules already present"

	if [ "$OPT_LIST" -eq 1 ]; then
		print_list
		exit 0
	fi

	if [ "$OPT_YES" -eq 1 ] || [ -n "$OPT_PROFILE" ] || [ ! -t 0 ]; then
		select_headless
	else
		select_interactive || die "cancelled"
	fi

	if [ ! -s "$SELECT_FILE" ]; then
		log_head "Nothing to do"
		log_dim "  everything selected is already installed"
		exit 0
	fi

	if [ -n "$OPT_SAVE_PROFILE" ]; then
		cp "$SELECT_FILE" "$OPT_SAVE_PROFILE"
		log_ok "selection saved to $OPT_SAVE_PROFILE"
	fi

	log_head "Installing"
	awk '{printf "  %s\n", $0}' "$SELECT_FILE"

	if [ "$OPT_DRY_RUN" -eq 0 ]; then
		offer_swap
		env_init
	fi
	install_selection
}

main "$@"
