#!/bin/sh
# Package manager abstraction. Only apt is implemented today; every other
# manager reports as unsupported rather than guessing at package names.

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
#
# Every module runs as its own process, so "already refreshed" cannot live in a
# variable. install.sh points DVB_RUN_DIR at its per-run temporary directory
# and the refresh leaves a stamp there. A module run on its own has no run
# directory and refreshes for itself, which is what a one-off run should do.
pkg_refresh() {
	pkg_supported || return 1

	stamp=""
	[ -n "${DVB_RUN_DIR:-}" ] && stamp="$DVB_RUN_DIR/apt-refreshed"
	[ -n "$stamp" ] && [ -f "$stamp" ] && return 0

	log_dim "  refreshing package index"
	as_root apt-get update -qq || return 1
	[ -n "$stamp" ] && : > "$stamp"
	return 0
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
#
# The key is dearmored when the fetched bytes are ASCII-armored (how most
# vendors publish a signing key) and installed verbatim when they are already
# binary (as GitHub CLI's keyring is): apt's signed-by option only accepts
# the binary form.
#
# If the index refresh that follows fails, the list file just written is
# removed again. Left in place, a bad repository entry fails pkg_refresh --
# and with it every pkg_install -- for the rest of the run, and every run
# after that, since the check above treats the list file's mere presence as
# "already done".
pkg_add_repo() {
	repo_name="$1"
	key_url="$2"
	source_body="$3"
	keyring="/etc/apt/keyrings/${repo_name}.gpg"
	list="/etc/apt/sources.list.d/${repo_name}.list"

	[ -f "$list" ] && return 0

	as_root install -m 0755 -d /etc/apt/keyrings || return 1

	key_tmp="$(mktemp)"
	fetch_to_stdout "$key_url" > "$key_tmp" || {
		rm -f "$key_tmp"
		return 1
	}

	if head -1 "$key_tmp" | grep -q '^-----BEGIN PGP PUBLIC KEY BLOCK-----'; then
		command -v gpg >/dev/null 2>&1 || pkg_install gnupg || {
			rm -f "$key_tmp"
			return 1
		}
		as_root gpg --dearmor --yes -o "$keyring" < "$key_tmp" || {
			rm -f "$key_tmp"
			return 1
		}
	else
		as_root install -m 0644 "$key_tmp" "$keyring" || {
			rm -f "$key_tmp"
			return 1
		}
	fi
	rm -f "$key_tmp"

	as_root chmod a+r "$keyring" || return 1
	printf '%s\n' "$source_body" | as_root tee "$list" >/dev/null || return 1
	# The new repository is not in the index the stamp vouches for.
	[ -n "${DVB_RUN_DIR:-}" ] && rm -f "$DVB_RUN_DIR/apt-refreshed"
	if ! pkg_refresh; then
		as_root rm -f "$list"
		return 1
	fi
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
