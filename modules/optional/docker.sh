#!/bin/sh
# Distro Docker plus the compose plugin. Adds the invoking user to the docker
# group, which takes effect on their next login.

DOCKER_PACKAGES="docker.io docker-compose-v2"

dvb_check() {
	command -v docker >/dev/null 2>&1 || return 1
	docker --version 2>/dev/null | awk '{print "docker", substr($3, 1, length($3) - 1)}'
}

dvb_install() {
	# shellcheck disable=SC2086
	pkg_install $DOCKER_PACKAGES || return 1

	target_user="${SUDO_USER:-$(id -un)}"
	if ! id -nG "$target_user" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
		as_root usermod -aG docker "$target_user" || return 1
		log_warn "added $target_user to the docker group; log out and back in for it to apply"
	fi
}
