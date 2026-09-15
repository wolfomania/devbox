#!/bin/sh
# Distro Ruby with the development headers, enough for gem installs.

RUBY_PACKAGES="ruby-full ruby-dev"

dvb_check() {
	command -v ruby >/dev/null 2>&1 || return 1
	ruby --version 2>/dev/null | awk '{print $1, $2}'
}

dvb_install() {
	# shellcheck disable=SC2086
	pkg_install $RUBY_PACKAGES
}
