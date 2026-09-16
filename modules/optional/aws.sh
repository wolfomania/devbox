#!/bin/sh
# AWS CLI v2 from Amazon's own zip installer. Amazon publishes no versioned
# URL, only a rolling "latest" per architecture, so there is nothing to pin
# beyond that; the installer itself is asked to target $HOME so no root is
# needed.
#
#   modules/optional/aws.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

aws_zip_url() {
	case "$DVB_ARCH" in
		amd64) printf '%s\n' "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
		arm64) printf '%s\n' "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
		*)
			log_err "no AWS CLI build for architecture $DVB_ARCH"
			return 1
			;;
	esac
}

dvb_check() {
	command -v aws >/dev/null 2>&1 || return 1
	aws --version 2>/dev/null | awk -F'[ /]' '{print "aws", $2}'
}

dvb_install() {
	if ! command -v unzip >/dev/null 2>&1; then
		if [ "$DVB_CAN_ROOT" -eq 1 ]; then
			pkg_install unzip || return 1
		else
			log_err "unzip not found and no root available to install it"
			return 1
		fi
	fi

	url="$(aws_zip_url)" || return 1
	env_init

	tmp="$(mktemp -d)"
	log_dim "  fetching ${url##*/}"
	if ! fetch_to_file "$url" "$tmp/awscliv2.zip"; then
		rm -rf "$tmp"
		return 1
	fi

	unzip -q "$tmp/awscliv2.zip" -d "$tmp" || {
		rm -rf "$tmp"
		return 1
	}

	# Positional parameters, not a word-split string: $DVB_PREFIX and $DVB_BIN
	# both derive from $HOME, and a home directory containing a space would
	# otherwise split into the wrong -i/-b targets.
	set -- -i "$DVB_PREFIX/aws-cli" -b "$DVB_BIN"
	[ -x "$DVB_PREFIX/aws-cli/v2/current/bin/aws" ] && set -- "$@" --update

	install_log="$tmp/install.log"
	if ! "$tmp/aws/install" "$@" >"$install_log" 2>&1; then
		log_err "aws installer failed:"
		cat "$install_log" >&2
		rm -rf "$tmp"
		return 1
	fi

	rm -rf "$tmp"
	[ -x "$DVB_BIN/aws" ]
}

dvb_main "$@"
