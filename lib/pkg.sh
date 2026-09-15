#!/bin/sh
# Package manager abstraction. Only apt is implemented today; every other
# manager reports as unsupported rather than guessing at package names.

DVB_PKG_REFRESHED=0

# Run a command with root privileges, or fail clearly if that is impossible.
as_root() {
	case "$DVB_PRIV" in
		root) "$@" ;;
		sudo | sudo-password) sudo "$@" ;;
		none)
			log_err "root required for: $*"
			return 1
			;;
	esac
}

pkg_supported() {
	[ "$DVB_PKG" = "apt" ]
}

# Refresh the package index at most once per run.
pkg_refresh() {
	[ "$DVB_PKG_REFRESHED" -eq 0 ] || return 0
	pkg_supported || return 1
	log_dim "  refreshing package index"
	as_root apt-get update -qq || return 1
	DVB_PKG_REFRESHED=1
}

pkg_installed() {
	pkg_supported || return 1
	dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null | grep -q '^installed$'
}

pkg_version() {
	pkg_supported || return 1
	dpkg-query -W -f='${Version}' "$1" 2>/dev/null
}

# Install packages, skipping any that dpkg already reports as installed.
pkg_install() {
	pkg_supported || {
		log_err "package manager '$DVB_PKG' is not supported yet"
		return 1
	}

	missing=""
	for p in "$@"; do
		pkg_installed "$p" || missing="$missing $p"
	done

	if [ -z "$missing" ]; then
		log_dim "  all packages already present"
		return 0
	fi

	pkg_refresh || return 1
	log_dim "  installing:$missing"
	# shellcheck disable=SC2086
	DEBIAN_FRONTEND=noninteractive as_root apt-get install -y -qq --no-install-recommends $missing
}

# Register an apt repository from a keyring URL and a deb822 source body.
pkg_add_repo() {
	repo_name="$1"
	key_url="$2"
	source_body="$3"
	keyring="/etc/apt/keyrings/${repo_name}.gpg"

	[ -f "/etc/apt/sources.list.d/${repo_name}.list" ] && return 0

	as_root install -m 0755 -d /etc/apt/keyrings || return 1
	fetch_to_stdout "$key_url" | as_root tee "$keyring" >/dev/null || return 1
	as_root chmod a+r "$keyring" || return 1
	printf '%s\n' "$source_body" | as_root tee "/etc/apt/sources.list.d/${repo_name}.list" >/dev/null || return 1
	DVB_PKG_REFRESHED=0
	pkg_refresh
}

# Download a URL to stdout using whichever fetcher the box has.
fetch_to_stdout() {
	case "$DVB_NET_TOOL" in
		curl) curl -fsSL "$1" ;;
		wget) wget -qO- "$1" ;;
		*)
			log_err "no curl or wget available to fetch $1"
			return 1
			;;
	esac
}

# Download a URL to a file.
fetch_to_file() {
	case "$DVB_NET_TOOL" in
		curl) curl -fsSL -o "$2" "$1" ;;
		wget) wget -qO "$2" "$1" ;;
		*)
			log_err "no curl or wget available to fetch $1"
			return 1
			;;
	esac
}
