#!/bin/sh
# Install one module from nothing, and check that it worked.
#
#   tests/module-case.sh go
#
# Three questions, in this order:
#
#   check    must fail. A check that reports a tool as present on a machine
#            that does not have it is how a run ends up installing nothing and
#            announcing that everything is already there.
#   install  must succeed.
#   check    must now succeed, and print a version.
#
# Anything the module declares as a dependency is installed first, quietly,
# because the module under test cannot be expected to work without it.
#
# This installs software for real, so it only ever runs on a machine that can
# be thrown away: a container started by tests/modules/run.sh, or a disposable
# instance started by tests/vps/run.sh. It refuses to run anywhere else unless
# DVB_TEST_DISPOSABLE says otherwise.

set -u

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TARGET="${1:-}"

[ -n "$TARGET" ] || {
	echo "usage: tests/module-case.sh MODULE_ID" >&2
	exit 2
}

fail() {
	printf 'TEST-FAIL %s\n' "$*"
	exit 1
}

# A container and a freshly launched instance both say so in /run or in the
# environment. Anything else is somebody's actual machine.
assert_disposable() {
	[ -n "${DVB_TEST_DISPOSABLE:-}" ] && return 0
	[ -f /.dockerenv ] && return 0
	fail "refusing to install on a machine that is not disposable; set DVB_TEST_DISPOSABLE=1 if it is"
}

manifest() {
	DVB_MANIFEST="${DVB_MANIFEST:-$ROOT/manifests}" python3 "$ROOT/tui/manifest.py" "$@"
}

main() {
	assert_disposable
	cd "$ROOT" || fail "cannot enter $ROOT"

	script="$(manifest field "$TARGET" script)" || fail "no module called $TARGET"

	# manifest order puts dependencies first and the module itself last.
	for dependency in $(manifest order "$TARGET"); do
		[ "$dependency" = "$TARGET" ] && break
		"./$(manifest field "$dependency" script)" install > /dev/null 2>&1 ||
			fail "the dependency $dependency did not install"
	done

	if "./$script" check > /dev/null 2>&1; then
		fail "check reported $TARGET as installed before it was installed"
	fi

	"./$script" install || fail "install failed"

	version="$("./$script" check)" ||
		fail "check still reports $TARGET as missing after installing it"
	[ -n "$version" ] || fail "check printed no version"

	printf 'TEST-OK %s\n' "$version"
}

main
