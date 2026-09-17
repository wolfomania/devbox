#!/bin/sh
# Node from NodeSource's apt repository. MOD_PIN is the major line, e.g. 24.
#
# The repository is per-major, so apt floats the patch releases from there on
# and `apt upgrade` keeps Node current without devbox being run again. That is
# the trade for needing root: nvm needed none, but nothing updated the version
# it installed except editing the manifest and running devbox a second time.
#
# nvm also had to go for a second reason. It is a bash script that defines
# shell functions, so putting node on PATH meant sourcing bash-only code from
# the managed env file, which every POSIX sh probe in this repository sources
# too. See the comment in lib/paths.sh load_env for what that cost.
#
#   modules/lang/node.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

NODE_KEY_URL="https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key"

dvb_check() {
	command -v node >/dev/null 2>&1 || return 1
	printf 'node %s\n' "$(node --version 2>/dev/null | tr -d v)"
}

dvb_install() {
	repo_line="deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${MOD_PIN}.x nodistro main"

	# Ubuntu carries its own nodejs, several major versions behind. It loses
	# on version number today, but the pin here is a major line and the
	# distro's is whatever the release froze on, so the two can cross. Naming
	# the origin settles it whichever way the numbers fall.
	printf 'Package: nodejs\nPin: origin deb.nodesource.com\nPin-Priority: 600\n' |
		as_root tee /etc/apt/preferences.d/devbox-nodejs >/dev/null || return 1

	pkg_add_repo "nodesource" "$NODE_KEY_URL" "$repo_line" || return 1
	pkg_install nodejs
}

dvb_main "$@"
