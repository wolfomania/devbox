#!/bin/sh
# Google Cloud CLI from Google's own apt repository, so gcloud components
# update in step with the rest of the system instead of drifting from a
# vendored tarball.
#
#   modules/optional/gcloud.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

GCLOUD_KEY_URL="https://packages.cloud.google.com/apt/doc/apt-key.gpg"

dvb_check() {
	command -v gcloud >/dev/null 2>&1 || return 1
	gcloud --version 2>/dev/null | awk 'NR==1 {print "gcloud", $NF}'
}

dvb_install() {
	# Google's published key is ASCII-armored; pkg_add_repo dearmors it
	# before apt sees it.
	repo_line="deb [signed-by=/etc/apt/keyrings/cloud-sdk.gpg] https://packages.cloud.google.com/apt cloud-sdk main"
	pkg_add_repo "cloud-sdk" "$GCLOUD_KEY_URL" "$repo_line" || return 1
	pkg_install google-cloud-cli
}

dvb_main "$@"
