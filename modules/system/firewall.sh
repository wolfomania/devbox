#!/bin/sh
# Firewall: ufw, denying every inbound connection except SSH.
#
# The provider's firewall (an AWS security group, a Hetzner cloud firewall) is
# the first line; this one still holds when that is misconfigured or missing.
# SSH stays open on whatever port sshd listens on, rate limited: ufw drops an
# address that opens 6 connections within 30 seconds. Rules already in ufw are
# kept.
#
# Docker bypasses ufw with its own iptables rules. The docker module makes
# published ports default to 127.0.0.1 for that reason.
#
#   modules/system/firewall.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

readonly UFW_CONF=/etc/ufw/ufw.conf
readonly SSH_DEFAULT_PORT=22

# /etc/ufw/ufw.conf is world-readable; `ufw status` needs root.
dvb_check() {
	command -v ufw >/dev/null 2>&1 || [ -x /usr/sbin/ufw ] || return 1
	grep -qx 'ENABLED=yes' "$UFW_CONF" 2>/dev/null || return 1
	printf 'ufw enabled\n'
}

dvb_install() {
	pkg_install ufw || return 1

	ports="$(ssh_ports)"
	for port in $ports; do
		as_root ufw limit "$port/tcp" comment 'ssh' > /dev/null || return 1
	done
	as_root ufw default deny incoming > /dev/null &&
		as_root ufw default allow outgoing > /dev/null &&
		as_root ufw --force enable > /dev/null || return 1
	log_dim "  inbound denied except ssh on $(printf '%s' "$ports" | tr '\n' ' ')"
}

# The ports sshd listens on, or 22 when sshd is absent or will not say. Opening
# 22 on a box with no sshd costs nothing and saves a lockout once one is added.
ssh_ports() {
	ports="$(as_root sshd -T 2>/dev/null | awk '$1 == "port" {print $2}' | sort -u)"
	printf '%s\n' "${ports:-$SSH_DEFAULT_PORT}"
}

dvb_main "$@"
