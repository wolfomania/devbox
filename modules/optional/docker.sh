#!/bin/sh
# Docker Engine and the compose plugin, from Docker's own apt repository.
# Adds the invoking user to the docker group, which takes effect on their
# next login.
#
# Not Ubuntu's docker.io: that one is only a few patch releases behind today,
# but it bundles its own containerd and runc, and the compose and buildx
# plugins arrive on the distro's schedule rather than Docker's. The vendor
# repository is also what Docker's own support matrix is written against.
#
#   modules/optional/docker.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

DOCKER_KEY_URL="https://download.docker.com/linux/ubuntu/gpg"
DOCKER_PACKAGES="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

dvb_check() {
	command -v docker >/dev/null 2>&1 || return 1
	docker --version 2>/dev/null | awk '{print "docker", substr($3, 1, length($3) - 1)}'
}

dvb_install() {
	# lsb_release may not be installed in a minimal container; the codename
	# is in /etc/os-release regardless of distro tooling. UBUNTU_CODENAME is
	# read first because a derivative sets VERSION_CODENAME to its own
	# release name, which Docker publishes nothing for.
	[ -r /etc/os-release ] || {
		log_err "cannot find /etc/os-release to read the distro codename"
		return 1
	}
	codename="$(. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
	[ -n "$codename" ] || {
		log_err "no codename in /etc/os-release"
		return 1
	}

	arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
	# Docker's published key is ASCII-armored; pkg_add_repo dearmors it
	# before apt sees it.
	repo_line="deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable"

	pkg_add_repo "docker" "$DOCKER_KEY_URL" "$repo_line" || return 1
	# shellcheck disable=SC2086
	pkg_install $DOCKER_PACKAGES || return 1

	target_user="${SUDO_USER:-$(id -un)}"
	if ! id -nG "$target_user" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
		as_root usermod -aG docker "$target_user" || return 1
		log_warn "added $target_user to the docker group; log out and back in for it to apply"
	fi
}

dvb_main "$@"
