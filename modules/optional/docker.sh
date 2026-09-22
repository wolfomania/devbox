#!/bin/sh
# Docker Engine and the compose plugin, from Docker's own apt repository.
# Adds the account devbox provisions to the docker group, which takes effect on their
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
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
# A port published as -p 5432:5432 listens on this address.
DOCKER_BIND_IP="127.0.0.1"

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
	# Written before the packages, so the daemon's first start already
	# reads it.
	docker_bind_localhost || return 1
	# shellcheck disable=SC2086
	pkg_install $DOCKER_PACKAGES || return 1
	if [ "$DOCKER_CONFIG_CHANGED" -eq 1 ] && systemctl is-active --quiet docker 2>/dev/null; then
		as_root systemctl restart docker || return 1
	fi

	target_user="${DVB_USER:-${SUDO_USER:-$(id -un)}}"
	if ! id -nG "$target_user" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
		as_root usermod -aG docker "$target_user" || return 1
		log_warn "added $target_user to the docker group; log out and back in for it to apply"
	fi
}

# Publish container ports on localhost unless a run names another address.
#
# Docker writes its own iptables rules ahead of ufw's, so a port published on
# every interface is open to the internet whatever the host firewall says.
# Reach a published port through an SSH tunnel instead. An explicit
# -p 0.0.0.0:5432:5432 still opens it; this changes only the default.
#
# Other keys in an existing daemon.json are kept.
docker_bind_localhost() {
	DOCKER_CONFIG_CHANGED=0
	[ -n "$DVB_PYTHON" ] || {
		log_err "python3 is required to edit $DOCKER_DAEMON_JSON"
		return 1
	}

	current="$(as_root cat "$DOCKER_DAEMON_JSON" 2>/dev/null || true)"
	merged="$(printf '%s' "$current" | "$DVB_PYTHON" -c '
import json, sys
text = sys.stdin.read().strip()
config = json.loads(text) if text else {}
config["ip"] = sys.argv[1]
print(json.dumps(config, indent=2, sort_keys=True))
' "$DOCKER_BIND_IP")" || {
		log_err "$DOCKER_DAEMON_JSON is not valid JSON; leaving it alone"
		return 1
	}
	[ "$merged" = "$current" ] && return 0

	as_root mkdir -p "$(dirname "$DOCKER_DAEMON_JSON")" &&
		printf '%s\n' "$merged" | as_root tee "$DOCKER_DAEMON_JSON" > /dev/null || return 1
	DOCKER_CONFIG_CHANGED=1
	log_dim "  published ports default to $DOCKER_BIND_IP"
}

dvb_main "$@"
