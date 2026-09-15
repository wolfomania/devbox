#!/bin/sh
# Swap: a swapfile for a box with too little memory to build on.
#
# The check is the suggestion. A box with enough memory reports as satisfied,
# so the selection screen shows it green and installs nothing; a small box
# reports as missing and the screen offers it ticked, at the top of the list,
# ahead of every toolchain that would run out of memory without it.
#
# The numbers live in lib/swap.sh, which decides what "too little" means and
# how large a swapfile to make.
#
#   modules/system/swap.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"
# shellcheck source=../../lib/swap.sh
. "$DVB_ROOT/lib/swap.sh"

dvb_check() {
	# Re-read /proc/meminfo rather than trust what was detected at startup: a
	# previous module in the same run may have turned swap on.
	detect_memory
	swap_is_low && return 1
	printf '%d MiB usable\n' "$((DVB_RAM_MB + DVB_SWAP_MB))"
}

dvb_install() {
	detect_memory
	if ! swap_is_low; then
		log_dim "  $((DVB_RAM_MB + DVB_SWAP_MB)) MiB of memory is enough; no swapfile needed"
		return 0
	fi

	if ! swap_can_create; then
		log_err "cannot add swap here: it needs root, more than $((SWAP_CREATE_MB + 1024)) MiB free, and no existing $SWAP_PATH"
		return 1
	fi

	swap_create
}

dvb_main "$@"
