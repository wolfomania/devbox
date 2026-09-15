#!/bin/sh
# Swapfile provisioning for low-memory boxes.
#
# Nothing here runs without explicit consent: install.sh asks, and only calls
# swap_create on a yes. A box that already has enough memory is left alone.

# Below this much usable memory, toolchain installs (rustup in particular)
# start failing on small VPSes.
readonly SWAP_THRESHOLD_MB=2048
# Size of the swapfile we offer to create.
readonly SWAP_CREATE_MB=2048
readonly SWAP_PATH=/swapfile

swap_is_low() {
	total=$((DVB_RAM_MB + DVB_SWAP_MB))
	[ "$total" -lt "$SWAP_THRESHOLD_MB" ]
}

swap_can_create() {
	[ "$DVB_CAN_ROOT" -eq 1 ] || return 1
	[ ! -e "$SWAP_PATH" ] || return 1
	[ "$DVB_DISK_FREE_MB" -gt $((SWAP_CREATE_MB + 1024)) ] || return 1
	command -v mkswap >/dev/null 2>&1
}

# Create, enable and persist a swapfile. Every step is reversible with
# `swapoff /swapfile && rm /swapfile` plus removing the fstab line.
swap_create() {
	log_step "Creating a ${SWAP_CREATE_MB} MiB swapfile at $SWAP_PATH"

	if command -v fallocate >/dev/null 2>&1; then
		as_root fallocate -l "${SWAP_CREATE_MB}M" "$SWAP_PATH" || return 1
	else
		as_root dd if=/dev/zero of="$SWAP_PATH" bs=1M count="$SWAP_CREATE_MB" status=none || return 1
	fi

	as_root chmod 600 "$SWAP_PATH" || return 1
	as_root mkswap "$SWAP_PATH" >/dev/null || return 1
	as_root swapon "$SWAP_PATH" || return 1

	if ! grep -q "^$SWAP_PATH " /etc/fstab 2>/dev/null; then
		printf '%s none swap sw 0 0\n' "$SWAP_PATH" | as_root tee -a /etc/fstab >/dev/null
	fi

	detect_memory
	log_ok "swap enabled, now ${DVB_SWAP_MB} MiB"
}
