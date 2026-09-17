#!/bin/sh
# Helm from the canonical tarball at get.helm.sh, which is what Helm's own
# install script uses. Unpacked under $HOME, so no root is needed.
#
# MOD_PIN is "latest", which is what the manifest says, or an exact version.
# Helm publishes its newest release as one line of plain text at
# get.helm.sh/helm-latest-version; its GitHub assets carry the version in
# their names, so there is no redirect to fetch through instead.
#
# The Helm apt repository at baltocdn.com no longer resolves, so apt is not
# an option here however much the rest of this repository prefers it.
#
#   modules/optional/helm.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	command -v helm >/dev/null 2>&1 || return 1
	helm version --short 2>/dev/null | awk '{sub(/^v/, "", $1); sub(/\+.*/, "", $1); print "helm", $1}'
}

helm_release() {
	if [ "$MOD_PIN" != "latest" ]; then
		printf '%s\n' "$MOD_PIN"
		return 0
	fi

	release="$(fetch_to_stdout "https://get.helm.sh/helm-latest-version" | tr -d '[:space:]')"
	case "$release" in
		v[0-9]*) printf '%s\n' "${release#v}" ;;
		*)
			log_err "get.helm.sh did not answer with a version"
			return 1
			;;
	esac
}

dvb_install() {
	release="$(helm_release)" || return 1
	url="https://get.helm.sh/helm-v${release}-linux-${DVB_ARCH}.tar.gz"

	fetch_bin_from_tar "$url" "linux-${DVB_ARCH}/helm" helm
}

dvb_main "$@"
