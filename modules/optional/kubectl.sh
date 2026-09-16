#!/bin/sh
# kubectl from the pkgs.k8s.io apt repository, whose path is versioned by
# Kubernetes minor rather than by distro, so the pin tracks upstream
# directly instead of whatever the distro's own kubernetes-client trails.
#
#   modules/optional/kubectl.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v kubectl >/dev/null 2>&1 || return 1
	version="$(kubectl version --client 2>/dev/null | head -1 | awk '{print substr($3, 2)}')"
	# Google's apt repo (modules/optional/gcloud.sh) also ships a package
	# literally named "kubectl": a dispatcher stub that reports itself as
	# "<version>-dispatcher" until a separate, gcloud-managed component
	# download completes. That is not a working client, so it must not read
	# as one here.
	case "$version" in
		*-dispatcher | "") return 1 ;;
	esac
	printf 'kubectl %s\n' "$version"
}

dvb_install() {
	key_url="https://pkgs.k8s.io/core:/stable:/v${MOD_PIN}/deb/Release.key"
	repo_line="deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v${MOD_PIN}/deb/ /"
	list="/etc/apt/sources.list.d/kubernetes.list"
	need_reinstall=0

	# The pin lives inside the repository URL, not in a package version apt
	# can compare against. pkg_add_repo only checks whether the list file
	# exists, so a file left behind by an earlier pin would otherwise be
	# trusted as-is and this module would quietly install that older minor
	# while the manifest and the selection screen both claim $MOD_PIN.
	if [ -f "$list" ] && ! grep -qxF "$repo_line" "$list"; then
		as_root rm -f "$list" /etc/apt/keyrings/kubernetes.gpg || return 1
		need_reinstall=1
	fi

	# Google's cloud-sdk apt repo carries its own "kubectl" package (the
	# dispatcher stub dvb_check rejects above), versioned to mirror gcloud's
	# own release train under a "1:" epoch. An epoch always outranks a
	# real Kubernetes version in apt's eyes, so once that repo is
	# registered, plain `apt-get install kubectl` picks the dispatcher over
	# the real client regardless of which module ran first or which repo
	# was added last. Pinning the package out by its origin keeps the
	# pkgs.k8s.io copy authoritative whether or not gcloud is installed.
	printf 'Package: kubectl\nPin: release o=cloud-sdk\nPin-Priority: -1\n' |
		as_root tee /etc/apt/preferences.d/devbox-kubectl >/dev/null || return 1

	# The Release.key is ASCII-armored; pkg_add_repo dearmors it before apt
	# sees it.
	pkg_add_repo "kubernetes" "$key_url" "$repo_line" || return 1

	# A "kubectl" that dpkg considers installed but that dvb_check rejects
	# is gcloud's dispatcher, pulled in before the pin above existed (or
	# before the pkgs.k8s.io repo did). pkg_install only checks presence by
	# name, so it would otherwise leave the stub in place forever.
	if [ "$need_reinstall" -eq 0 ] && pkg_installed kubectl && ! dvb_check > /dev/null 2>&1; then
		need_reinstall=1
	fi

	# pkg_install skips a package dpkg already reports as installed, by name
	# only, never by version or origin. Removing it first makes it "missing"
	# again, so pkg_install pulls the pinned version fresh from the
	# corrected repo.
	if [ "$need_reinstall" -eq 1 ] && pkg_installed kubectl; then
		as_root apt-get remove -y -qq kubectl || return 1
	fi

	pkg_install kubectl
}

dvb_main "$@"
