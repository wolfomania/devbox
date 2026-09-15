#!/bin/sh
# Machine detection. Every function here is read-only: nothing in this file
# changes the host. Results are cached in DVB_* variables by detect_all.

# Bytes per MiB, used to convert /proc/meminfo kB readings.
readonly KB_PER_MIB=1024

detect_os() {
	if [ -r /etc/os-release ]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		DVB_OS_ID="${ID:-unknown}"
		DVB_OS_LIKE="${ID_LIKE:-}"
		DVB_OS_VERSION="${VERSION_ID:-unknown}"
		DVB_OS_NAME="${PRETTY_NAME:-$DVB_OS_ID $DVB_OS_VERSION}"
	else
		DVB_OS_ID="unknown"
		DVB_OS_LIKE=""
		DVB_OS_VERSION="unknown"
		DVB_OS_NAME="$(uname -s) $(uname -r)"
	fi
	DVB_KERNEL="$(uname -sr)"
}

detect_arch() {
	DVB_ARCH_RAW="$(uname -m)"
	case "$DVB_ARCH_RAW" in
		x86_64 | amd64) DVB_ARCH=amd64 ;;
		aarch64 | arm64) DVB_ARCH=arm64 ;;
		armv7l) DVB_ARCH=armv6l ;;
		*) DVB_ARCH="$DVB_ARCH_RAW" ;;
	esac
	if [ -n "$(ldd --version 2>&1 | grep -i musl)" ]; then
		DVB_LIBC=musl
	else
		DVB_LIBC=gnu
	fi
}

detect_pkg_manager() {
	if command -v apt-get >/dev/null 2>&1; then
		DVB_PKG=apt
	elif command -v dnf >/dev/null 2>&1; then
		DVB_PKG=dnf
	elif command -v pacman >/dev/null 2>&1; then
		DVB_PKG=pacman
	elif command -v apk >/dev/null 2>&1; then
		DVB_PKG=apk
	elif command -v brew >/dev/null 2>&1; then
		DVB_PKG=brew
	else
		DVB_PKG=none
	fi
}

# Sets DVB_PRIV to one of: root, sudo, sudo-password, none
detect_privilege() {
	if [ "$(id -u)" -eq 0 ]; then
		DVB_PRIV=root
	elif ! command -v sudo >/dev/null 2>&1; then
		DVB_PRIV=none
	elif sudo -n true 2>/dev/null; then
		DVB_PRIV=sudo
	else
		DVB_PRIV=sudo-password
	fi

	case "$DVB_PRIV" in
		root | sudo | sudo-password) DVB_CAN_ROOT=1 ;;
		*) DVB_CAN_ROOT=0 ;;
	esac
}

detect_memory() {
	DVB_RAM_MB=0
	DVB_SWAP_MB=0
	if [ -r /proc/meminfo ]; then
		DVB_RAM_MB=$(awk -v d="$KB_PER_MIB" '/^MemTotal:/ {printf "%d", $2 / d}' /proc/meminfo)
		DVB_SWAP_MB=$(awk -v d="$KB_PER_MIB" '/^SwapTotal:/ {printf "%d", $2 / d}' /proc/meminfo)
	elif command -v sysctl >/dev/null 2>&1; then
		DVB_RAM_MB=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%d", $1 / 1048576}')
	fi
	[ -n "$DVB_RAM_MB" ] || DVB_RAM_MB=0
	[ -n "$DVB_SWAP_MB" ] || DVB_SWAP_MB=0
}

detect_disk() {
	DVB_DISK_FREE_MB=$(df -Pm "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
	[ -n "$DVB_DISK_FREE_MB" ] || DVB_DISK_FREE_MB=0
}

detect_python() {
	DVB_PYTHON=""
	for candidate in python3 python; do
		if command -v "$candidate" >/dev/null 2>&1; then
			if "$candidate" -c 'import sys, curses; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
				DVB_PYTHON="$(command -v "$candidate")"
				break
			fi
		fi
	done
}

detect_network() {
	if command -v curl >/dev/null 2>&1; then
		DVB_NET_TOOL=curl
	elif command -v wget >/dev/null 2>&1; then
		DVB_NET_TOOL=wget
	else
		DVB_NET_TOOL=none
	fi
}

detect_all() {
	detect_os
	detect_arch
	detect_pkg_manager
	detect_privilege
	detect_memory
	detect_disk
	detect_python
	detect_network
}

# Hand the detection results to child processes.
#
# Every module runs as its own process and would otherwise re-detect the
# machine, which is a dozen extra commands per module and the same answer
# every time. A module run on its own finds none of these set and detects for
# itself.
detect_export() {
	export DVB_OS_ID DVB_OS_LIKE DVB_OS_VERSION DVB_OS_NAME DVB_KERNEL
	export DVB_ARCH DVB_ARCH_RAW DVB_LIBC
	export DVB_PKG DVB_PRIV DVB_CAN_ROOT
	export DVB_RAM_MB DVB_SWAP_MB DVB_DISK_FREE_MB
	export DVB_PYTHON DVB_NET_TOOL
}

# Human-readable summary of everything detect_all found.
detect_report() {
	log_head "Machine"
	printf '  %-12s %s\n' "os" "$DVB_OS_NAME"
	printf '  %-12s %s\n' "kernel" "$DVB_KERNEL"
	printf '  %-12s %s (%s libc)\n' "arch" "$DVB_ARCH" "$DVB_LIBC"
	printf '  %-12s %s\n' "packages" "$DVB_PKG"
	printf '  %-12s %s MiB ram, %s MiB swap\n' "memory" "$DVB_RAM_MB" "$DVB_SWAP_MB"
	printf '  %-12s %s MiB free in %s\n' "disk" "$DVB_DISK_FREE_MB" "$HOME"

	case "$DVB_PRIV" in
		root) printf '  %-12s running as root\n' "privileges" ;;
		sudo) printf '  %-12s sudo available without a password\n' "privileges" ;;
		sudo-password) printf '  %-12s sudo available, will prompt for a password\n' "privileges" ;;
		none) printf '  %-12s %sno root access%s\n' "privileges" "$C_YELLOW" "$C_RESET" ;;
	esac
}
