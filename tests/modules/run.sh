#!/bin/sh
# Install one module, on its own, in a throwaway container, and check that it
# worked.
#
#   ./tests/modules/run.sh                 every module and bundle part
#   ./tests/modules/run.sh go ripgrep      only these
#   ./tests/modules/run.sh --all           including the slow ones
#   ./tests/modules/run.sh --list          what would run, and what is skipped
#   ./tests/modules/run.sh --keep          keep the container of a failing module
#
# What happens inside the container is tests/module-case.sh, which the VPS
# harness runs too, so both tiers ask a module the same questions.
#
# The container starts from an image with the required modules already in it,
# because install.sh always installs those first; the required modules
# themselves are tested from a bare Ubuntu.

set -u

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
IMAGE_BARE="devbox-test:bare"
IMAGE_READY="devbox-test:ready"
BASE_IMAGE="${DVB_TEST_IMAGE:-ubuntu:24.04}"

# Needs a real machine, not a container: covered by tests/vps instead.
# /proc/meminfo is not namespaced and swapon either fails in a container or,
# under --privileged, adds swap to the host, so swap belongs in that tier too.
SKIP_MODULES="docker swap"
# Correct in a container but too large to run on every change. --all includes
# them.
SLOW_MODULES="latex"

OPT_ALL=0
OPT_LIST=0
OPT_KEEP=0

# --- output ----------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	C_RESET=$(printf '\033[0m')
	C_DIM=$(printf '\033[2m')
	C_BOLD=$(printf '\033[1m')
	C_RED=$(printf '\033[31m')
	C_GREEN=$(printf '\033[32m')
	C_YELLOW=$(printf '\033[33m')
else
	C_RESET='' C_DIM='' C_BOLD='' C_RED='' C_GREEN='' C_YELLOW=''
fi

say() { printf '%s\n' "$*"; }
head_line() { printf '\n%s%s%s\n%s\n' "$C_BOLD" "$*" "$C_RESET" "-----------------------------------------------------------"; }
die() {
	printf '%sfail%s  %s\n' "$C_RED" "$C_RESET" "$*" >&2
	exit 1
}

# --- docker ----------------------------------------------------------------

# Some boxes need sudo to reach the daemon, some do not.
find_docker() {
	if [ -n "${DVB_TEST_DOCKER:-}" ]; then
		DOCKER="$DVB_TEST_DOCKER"
	elif docker info >/dev/null 2>&1; then
		DOCKER="docker"
	elif sudo -n docker info >/dev/null 2>&1; then
		DOCKER="sudo docker"
	else
		die "cannot reach a docker daemon (tried docker, sudo docker)"
	fi
}

# Two images, built once and reused: a bare one for the required modules, and
# one with the required modules already installed for everything else.
build_images() {
	head_line "Images"

	say "  $IMAGE_BARE"
	$DOCKER build -q -t "$IMAGE_BARE" -f - "$ROOT" > /dev/null <<DOCKERFILE || die "could not build $IMAGE_BARE"
FROM $BASE_IMAGE
ENV DEBIAN_FRONTEND=noninteractive
# python3 reads the manifest, and devbox requires it of any box it provisions.
RUN apt-get update -qq \\
 && apt-get install -y -qq --no-install-recommends python3 \\
 && rm -rf /var/lib/apt/lists/*
COPY install.sh /opt/devbox/install.sh
COPY lib /opt/devbox/lib
COPY tui /opt/devbox/tui
COPY modules /opt/devbox/modules
COPY manifests /opt/devbox/manifests
COPY tests /opt/devbox/tests
WORKDIR /opt/devbox
DOCKERFILE

	required="$(required_modules)"
	say "  $IMAGE_READY  ($(printf '%s' "$required" | tr '\n' ' '))"
	installs=""
	for id in $required; do
		installs="$installs && ./$(module_script "$id") install"
	done
	$DOCKER build -q -t "$IMAGE_READY" -f - "$ROOT" > /dev/null <<DOCKERFILE || die "could not build $IMAGE_READY"
FROM $IMAGE_BARE
RUN true $installs
DOCKERFILE
}

# --- the manifest ----------------------------------------------------------

manifest() { DVB_MANIFEST="$ROOT/manifests" python3 "$ROOT/tui/manifest.py" "$@"; }
module_script() { manifest field "$1" script; }
required_modules() { manifest rows | awk -F'\t' '{print $1}' | while read -r id; do
	[ "$(manifest field "$id" required)" = "True" ] && printf '%s\n' "$id"
done; }

# The parts of a bundle, which have no manifest entry and are named by file.
list_parts() {
	for path in "$ROOT"/modules/parts/*.sh; do
		[ -f "$path" ] || continue
		name="${path##*/}"
		printf '%s\n' "${name%.sh}"
	done
}

in_list() {
	for item in $2; do
		[ "$item" = "$1" ] && return 0
	done
	return 1
}

# Everything worth running, unless the caller named targets explicitly.
default_modules() {
	{ list_parts; manifest ids; } | while read -r id; do
		in_list "$id" "$SKIP_MODULES" && continue
		[ "$OPT_ALL" -eq 1 ] || ! in_list "$id" "$SLOW_MODULES" || continue
		printf '%s\n' "$id"
	done
}

# --- one module ------------------------------------------------------------

test_module() {
	id="$1"
	# A bare Ubuntu is the stricter test, so anything that can be installed on
	# one is: every bundle part is a plain apt package, and the required
	# modules are what a box gets before anything else.
	image="$IMAGE_READY"
	in_list "$id" "$(required_modules) $(list_parts | tr '\n' ' ')" && image="$IMAGE_BARE"

	log_file="$work_dir/$id.log"
	started="$(date +%s)"
	printf '  %-14s ' "$id"

	container="devbox-test-$id-$$"
	# This image was built for this test and has never had the tool, so a
	# check that passes before the install is a check that lies.
	if $DOCKER run --name "$container" -e DVB_TEST_PRISTINE=1 "$image" \
		sh tests/module-case.sh "$id" > "$log_file" 2>&1; then
		outcome=0
	else
		outcome=1
	fi
	elapsed=$(($(date +%s) - started))

	if [ "$outcome" -eq 0 ] && grep -q '^TEST-OK' "$log_file"; then
		version="$(sed -n 's/^TEST-OK //p' "$log_file" | tail -1)"
		printf '%sok%s   %-24s %ss\n' "$C_GREEN" "$C_RESET" "$version" "$elapsed"
		$DOCKER rm -f "$container" > /dev/null 2>&1
		return 0
	fi

	reason="$(sed -n 's/^TEST-FAIL //p' "$log_file" | tail -1)"
	[ -n "$reason" ] || reason="the container exited $outcome"
	printf '%sfail%s %-24s %ss\n' "$C_RED" "$C_RESET" "$reason" "$elapsed"
	printf '%s        log: %s%s\n' "$C_DIM" "$log_file" "$C_RESET"
	if [ "$OPT_KEEP" -eq 1 ]; then
		printf '%s        container kept: %s%s\n' "$C_DIM" "$container" "$C_RESET"
	else
		$DOCKER rm -f "$container" > /dev/null 2>&1
	fi
	return 1
}

# --- main ------------------------------------------------------------------

main() {
	wanted=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--all) OPT_ALL=1 ;;
			--list) OPT_LIST=1 ;;
			--keep) OPT_KEEP=1 ;;
			-h | --help)
				sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
				exit 0
				;;
			-*) die "unknown option: $1" ;;
			*) wanted="$wanted $1" ;;
		esac
		shift
	done

	[ -n "$wanted" ] || wanted="$(default_modules | tr '\n' ' ')"

	if [ "$OPT_LIST" -eq 1 ]; then
		head_line "Modules and bundle parts"
		{ list_parts; manifest ids; } | while read -r id; do
			if in_list "$id" "$SKIP_MODULES"; then
				printf '  %-14s %sskipped, needs a real machine (tests/vps)%s\n' "$id" "$C_YELLOW" "$C_RESET"
			elif in_list "$id" "$SLOW_MODULES"; then
				printf '  %-14s %sskipped unless --all, too large%s\n' "$id" "$C_DIM" "$C_RESET"
			else
				printf '  %-14s\n' "$id"
			fi
		done
		exit 0
	fi

	find_docker
	work_dir="$(mktemp -d "${TMPDIR:-/tmp}/devbox-modules.XXXXXX")"
	build_images

	head_line "Modules"
	failed=""
	for id in $wanted; do
		test_module "$id" || failed="$failed $id"
	done

	head_line "Result"
	if [ -n "$failed" ]; then
		printf '  %sfailed:%s%s\n' "$C_RED" "$C_RESET" "$failed"
		exit 1
	fi
	printf '  %severy module installed and reported its own version%s\n' "$C_GREEN" "$C_RESET"
}

main "$@"
