#!/bin/sh
# Terraform from HashiCorp's own apt repository. Terraform itself is BUSL 1.1
# licensed, not open source; modules/optional/opentofu.sh is the MPL-licensed
# fork for anyone who needs an OSI license instead.
#
#   modules/optional/terraform.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v terraform >/dev/null 2>&1 || return 1
	terraform version 2>/dev/null | head -1 | awk '{print "terraform", substr($2, 2)}'
}

dvb_install() {
	# lsb_release may not be installed in a minimal container; the codename
	# is in /etc/os-release regardless of distro tooling.
	[ -r /etc/os-release ] || { log_err "cannot find /etc/os-release to read the distro codename"; return 1; }
	codename="$(. /etc/os-release && printf '%s' "$VERSION_CODENAME")"
	[ -n "$codename" ] || { log_err "VERSION_CODENAME missing from /etc/os-release"; return 1; }

	# HashiCorp's gpg key is ASCII-armored; pkg_add_repo dearmors it before
	# apt sees it.
	repo_line="deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${codename} main"
	pkg_add_repo "hashicorp" "https://apt.releases.hashicorp.com/gpg" "$repo_line" || return 1

	pkg_install terraform
}

dvb_main "$@"
