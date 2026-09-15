#!/bin/sh
# Install one module from nothing, and check that it worked.
#
#   tests/module-case.sh go            a module, by its manifest id
#   tests/module-case.sh ripgrep       one part of a bundle, by its file name
#
# Three questions, in this order:
#
#   check    must fail, on a machine that has never had the tool. A check that
#            reports a tool as present when it is not is how a run ends up
#            installing nothing and announcing that everything is already
#            there. Only a container built for this test is known to be that
#            clean, so the runner says so with DVB_TEST_PRISTINE=1; a real box
#            may legitimately have the tool already, and the Ubuntu AMI ships
#            with git, so there the same result is only worth a note.
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
	case "${DVB_TEST_DISPOSABLE:-0}" in
		1 | y | yes | true) return 0 ;;
	esac
	[ -f /.dockerenv ] && return 0
	fail "refusing to install on a machine that is not disposable; set DVB_TEST_DISPOSABLE=1 if it is"
}

manifest() {
	DVB_MANIFEST="${DVB_MANIFEST:-$ROOT/manifests}" python3 "$ROOT/tui/manifest.py" "$@"
}

# A manifest id names a module; anything else is looked for among the bundle
# parts, which have no manifest entry of their own.
resolve_script() {
	if found="$(manifest field "$TARGET" script 2>/dev/null)" && [ -n "$found" ]; then
		printf '%s\n' "$found"
		return 0
	fi
	[ -f "$ROOT/modules/parts/$TARGET.sh" ] || return 1
	printf 'modules/parts/%s.sh\n' "$TARGET"
}

# Dependencies, in the order they have to be installed. A part declares none.
dependencies_of() {
	manifest order "$TARGET" 2>/dev/null | sed "/^$TARGET\$/d"
}

main() {
	assert_disposable
	cd "$ROOT" || fail "cannot enter $ROOT"

	script="$(resolve_script)" || fail "no module or bundle part called $TARGET"

	for dependency in $(dependencies_of); do
		"./$(manifest field "$dependency" script)" install > /dev/null 2>&1 ||
			fail "the dependency $dependency did not install"
	done

	if "./$script" check > /dev/null 2>&1; then
		case "${DVB_TEST_PRISTINE:-0}" in
			1 | y | yes | true)
				fail "check reported $TARGET as installed before it was installed"
				;;
		esac
		printf 'TEST-NOTE %s was already on this machine\n' "$TARGET"
	fi

	"./$script" install || fail "install failed"

	version="$("./$script" check)" ||
		fail "check still reports $TARGET as missing after installing it"
	[ -n "$version" ] || fail "check printed no version"

	# A command sent over SSM, a cron job and a systemd unit all arrive with
	# no HOME, and every path devbox writes hangs off it. The module has to
	# work that out for itself rather than die on an unset variable.
	env -u HOME "./$script" check > /dev/null 2>&1 ||
		fail "check fails when HOME is unset"

	printf 'TEST-OK %s\n' "$version"
}

main
