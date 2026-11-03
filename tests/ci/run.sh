#!/bin/sh
# Run the VPS tier on the machine this runs on: every module on its own, or
# one whole-install scenario, with the same checks tests/vps/run.sh makes on
# an EC2 instance. Meant for a GitHub Actions runner, a fresh VM that is
# thrown away after the job.
#
#   tests/ci/run.sh --modules                one module at a time, all of them
#   tests/ci/run.sh --modules docker,swap    only these
#   tests/ci/run.sh --modules --shard 2/4    every fourth one, from the second
#   tests/ci/run.sh --scenario minimal       install.sh as the scenario's user
#
# It installs software for real and changes the system, so it refuses to run
# unless DVB_TEST_DISPOSABLE=1. It needs root, and re-runs itself under sudo.

set -u

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
SRC=/opt/devbox-src
# Each module's own output, and nothing else, goes here.
LOGS_DIR="${DVB_TEST_LOGS:-/tmp/devbox-logs}"

OPT_SCENARIO=""
OPT_MODULES=""
OPT_SHARD=""

# --- output ----------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	C_RESET=$(printf '\033[0m'); C_DIM=$(printf '\033[2m'); C_BOLD=$(printf '\033[1m')
	C_RED=$(printf '\033[31m'); C_GREEN=$(printf '\033[32m'); C_BLUE=$(printf '\033[34m')
else
	C_RESET='' C_DIM='' C_BOLD='' C_RED='' C_GREEN='' C_BLUE=''
fi

say()  { printf '%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
dim()  { printf '%s    %s%s\n' "$C_DIM" "$*" "$C_RESET"; }
ok()   { printf '%s  ok%s  %s\n' "$C_GREEN" "$C_RESET" "$*"; }
err()  { printf '%sfail%s  %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
	sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
	exit 0
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
			--scenario) OPT_SCENARIO="${2:-}"; shift ;;
			--modules)
				OPT_MODULES="all"
				case "${2:-}" in
					-*|"") ;;
					*) OPT_MODULES="$2"; shift ;;
				esac
				;;
			--shard)    OPT_SHARD="${2:-}"; shift ;;
			-h|--help)  usage ;;
			*) die "unknown option: $1  (try --help)" ;;
		esac
		shift
	done

	[ -n "$OPT_MODULES" ] || [ -n "$OPT_SCENARIO" ] || usage
	[ -z "$OPT_MODULES" ] || [ -z "$OPT_SCENARIO" ] ||
		die "--modules and --scenario each need a machine of their own"
	if [ -n "$OPT_SHARD" ]; then
		[ -n "$OPT_MODULES" ] || die "--shard only applies to --modules"
		SHARD_K="${OPT_SHARD%%/*}"
		SHARD_N="${OPT_SHARD#*/}"
		case "$SHARD_K" in ''|*[!0-9]*) die "--shard takes K/N, as in 2/4" ;; esac
		case "$SHARD_N" in ''|*[!0-9]*) die "--shard takes K/N, as in 2/4" ;; esac
		[ "$SHARD_K" -ge 1 ] && [ "$SHARD_K" -le "$SHARD_N" ] ||
			die "--shard $OPT_SHARD: K must be between 1 and N"
	fi
}

# --- the machine -----------------------------------------------------------

preflight() {
	case "${DVB_TEST_DISPOSABLE:-0}" in
		1 | y | yes | true) ;;
		*) die "this installs software for real; set DVB_TEST_DISPOSABLE=1 on a machine you can throw away" ;;
	esac
	if [ "$(id -u)" -ne 0 ]; then
		exec sudo --preserve-env=DVB_TEST_DISPOSABLE,DVB_TEST_LOGS,GITHUB_TOKEN,NO_COLOR \
			sh "$0" "$@"
	fi
}

# A runner's /etc/environment points XDG_CONFIG_HOME at the runner user's
# home, and sudo hands it to every user it runs as, so devbox would write the
# account's config into the runner's home. A fresh VPS sets no such thing.
drop_runner_env() {
	unset XDG_CONFIG_HOME
	grep -q '^XDG_CONFIG_HOME=' /etc/environment 2>/dev/null || return 0
	sed -i '/^XDG_CONFIG_HOME=/d' /etc/environment
	dim "removed XDG_CONFIG_HOME from /etc/environment"
}

# The tree the tests run from, owned by whoever installs from it, as the EC2
# harness ships it.
ship_source() {
	owner="$1"
	rm -rf "$SRC"
	mkdir -p "$SRC" || die "cannot create $SRC"
	tar --exclude=.git --exclude=__pycache__ -cf - -C "$ROOT_DIR" . | tar -xf - -C "$SRC" ||
		die "cannot copy the tree to $SRC"
	chown -R "$owner:$owner" "$SRC"
}

# A cloud image logs in as a user with passwordless sudo, and the scenarios
# install as that user. A CI runner has its own user instead, so one is made
# the way cloud-init makes it.
ensure_user() {
	user="$1"
	id "$user" >/dev/null 2>&1 && return 0
	dim "creating $user, with passwordless sudo"
	useradd -m -s /bin/bash -G sudo "$user" || die "cannot create $user"
	printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$user" > "/etc/sudoers.d/90-devbox-test-$user"
	chmod 440 "/etc/sudoers.d/90-devbox-test-$user"
}

# --- modules ---------------------------------------------------------------

# The modules named, or every module in the manifest, cut down to one shard
# when asked. Round-robin, so the shards stay about even as modules are added.
module_list() {
	if [ "$OPT_MODULES" = "all" ]; then
		DVB_MANIFEST="$ROOT_DIR/manifests" python3 "$ROOT_DIR/tui/manifest.py" ids
	else
		printf '%s\n' "$OPT_MODULES" | tr ',' '\n'
	fi | sed '/^$/d' | if [ -n "$OPT_SHARD" ]; then
		awk -v k="$SHARD_K" -v n="$SHARD_N" '(NR - 1) % n == k - 1'
	else
		cat
	fi
}

# Install every module on its own, in order, as root, and report each one:
# the loop from tests/vps/run.sh.
run_modules() {
	wanted="$(module_list | tr '\n' ' ')"
	[ -n "$wanted" ] || die "no modules to run"
	ship_source root
	mkdir -p "$LOGS_DIR"
	say "Installing modules one at a time (as root)"
	dim "$wanted"

	failed=""
	for id in $wanted; do
		log="$LOGS_DIR/module-$id.log"
		t0=$(date +%s)
		if (cd "$SRC" && sh tests/module-case.sh "$id") > "$log" 2>&1; then
			printf '    ok    %-14s %-34s %ss\n' "$id" "$(sed -n 's/^TEST-OK //p' "$log" | tail -1)" "$(($(date +%s) - t0))"
		else
			failed="$failed $id"
			printf '    FAIL  %-14s %-34s %ss\n' "$id" "$(sed -n 's/^TEST-FAIL //p' "$log" | tail -1)" "$(($(date +%s) - t0))"
			tail -30 "$log" | sed 's/^/            /'
		fi
		sed -n 's/^TEST-NOTE /          note: /p' "$log"
	done

	printf '\n'
	[ -z "$failed" ] || die "modules failed:$failed"
	ok "every module installed and reported its own version"
}

# --- a scenario ------------------------------------------------------------

run_scenario() {
	scenario_file="$ROOT_DIR/tests/vps/scenarios/$OPT_SCENARIO.env"
	[ -r "$scenario_file" ] || die "no such scenario: $OPT_SCENARIO"
	# shellcheck source=/dev/null
	. "$scenario_file"

	ensure_user "$SCENARIO_USER"
	ship_source "$SCENARIO_USER"

	say "Installing (as $SCENARIO_USER, flags $SCENARIO_FLAGS)"
	runuser -l "$SCENARIO_USER" -c "cd $SRC && ./install.sh $SCENARIO_FLAGS" ||
		die "install.sh failed"

	say "Verifying"
	DVB_EXPECT="$SCENARIO_EXPECT" DVB_USER="${SCENARIO_ACCOUNT:-exclave}" DVB_SRC="$SRC" \
		DVB_FLAGS="$SCENARIO_FLAGS" sh "$ROOT_DIR/tests/vps/assert.sh" ||
		die "scenario '$OPT_SCENARIO' failed its checks"
	ok "scenario '$OPT_SCENARIO' passed"
}

# --- main ------------------------------------------------------------------

main() {
	parse_args "$@"
	preflight "$@"
	drop_runner_env
	if [ -n "$OPT_MODULES" ]; then
		run_modules
	else
		run_scenario
	fi
}

main "$@"
