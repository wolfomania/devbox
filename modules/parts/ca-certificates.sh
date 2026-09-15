#!/bin/sh
# The root certificate store, without which every https fetch fails.
#
#   modules/parts/ca-certificates.sh check | install
#
# One tool of the Build essentials bundle, modules/core/base.sh.
DVB_UNLISTED=1
. "$(dirname -- "$0")/../../lib/module.sh"

dvb_check() {
	# No command to run: this package is a bundle of certificates.
	[ -s /etc/ssl/certs/ca-certificates.crt ] || return 1
	printf 'ca-certificates %s\n' "$(grep -c 'BEGIN CERTIFICATE' /etc/ssl/certs/ca-certificates.crt)"
}

dvb_install() {
	pkg_install ca-certificates
}

dvb_main "$@"
