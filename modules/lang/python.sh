#!/bin/sh
# Python through uv: one binary that manages interpreters, venvs and tools,
# and then the interpreter itself. Installs entirely under $HOME, so no root
# is needed.
#
# MOD_PIN is the major line, e.g. 3.14. Patch releases float: uv resolves the
# line to its newest patch at install time, which is the point of pinning the
# line rather than the patch.
#
# uv itself is not pinned. It is a tool, not a runtime, and the rule for
# tools here is that they track their latest release.
#
#   modules/lang/python.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v uv >/dev/null 2>&1 || return 1
	# The interpreter this module installed, not whichever python3 the box
	# already had. Ubuntu ships one at /usr/bin/python3, and devbox requires
	# a python3 of its own to read the manifest at all, so reporting on bare
	# `python3` would report every box as already done.
	[ -x "$DVB_BIN/python3" ] || return 1
	version="$("$DVB_BIN/python3" --version 2>/dev/null | awk '{print $2}')"
	[ -n "$version" ] || return 1
	printf 'python %s\n' "$version"
}

dvb_install() {
	env_init

	log_dim "  fetching the uv installer"
	fetch_to_stdout "https://astral.sh/uv/install.sh" |
		env UV_INSTALL_DIR="$DVB_BIN" INSTALLER_NO_MODIFY_PATH=1 sh >/dev/null || return 1
	[ -x "$DVB_BIN/uv" ] || return 1

	# --default is what puts `python3` and `python` on PATH rather than only
	# a versioned `python3.14`. Without it this module installs an
	# interpreter that nothing but uv can find, which is how the module came
	# to report uv's own version as if it were Python's.
	log_dim "  uv python install $MOD_PIN"
	env UV_PYTHON_BIN_DIR="$DVB_BIN" "$DVB_BIN/uv" python install "$MOD_PIN" --default ||
		return 1

	env_add "# uv installs interpreters and tools into ~/.local/bin"
	[ -x "$DVB_BIN/python3" ]
}

dvb_main "$@"
