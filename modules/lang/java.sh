#!/bin/sh
# Eclipse Temurin from Adoptium's own apt repository. MOD_PIN is the major
# version, e.g. 25, and the package name carries it, so apt floats the
# quarterly updates within that line.
#
# Ubuntu's own openjdk packages would do as well, but only for the versions a
# given release happens to carry: noble froze on 21, and a 25 arrived there
# later only as a backport. Adoptium publishes every LTS line for every
# supported Ubuntu, which is the same reason gh and Docker come from their
# vendors here rather than from the distro.
#
# Adoptium ships no headless variant, so this is the full JDK.
#
#   modules/lang/java.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

ADOPTIUM_KEY_URL="https://packages.adoptium.net/artifactory/api/gpg/key/public"

dvb_check() {
	command -v javac >/dev/null 2>&1 || return 1
	javac -version 2>&1 | awk '{print "jdk", $2}'
}

dvb_install() {
	# lsb_release may not be installed in a minimal container; the codename
	# is in /etc/os-release regardless of distro tooling.
	[ -r /etc/os-release ] || {
		log_err "cannot find /etc/os-release to read the distro codename"
		return 1
	}
	codename="$(. /etc/os-release && printf '%s' "$VERSION_CODENAME")"
	[ -n "$codename" ] || {
		log_err "VERSION_CODENAME missing from /etc/os-release"
		return 1
	}

	# Adoptium's published key is ASCII-armored; pkg_add_repo dearmors it
	# before apt sees it.
	repo_line="deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${codename} main"
	pkg_add_repo "adoptium" "$ADOPTIUM_KEY_URL" "$repo_line" || return 1
	pkg_install "temurin-${MOD_PIN}-jdk"
}

dvb_main "$@"
