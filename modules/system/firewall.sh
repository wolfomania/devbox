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

# Every port sshd may listen on: what sshd reports, what its config files
# say, and what ssh.socket listens on when systemd starts sshd on demand, as
# Ubuntu 24.04 does. sshd -T alone fails there when /run/sshd is missing, and
# opening 22 while sshd sits on another port would lock the box. With none of
# these, sshd uses its default, 22; opening 22 on a box with no sshd costs
# nothing and saves a lockout once one is added.
ssh_ports() {
	{
		as_root sshd -T 2>/dev/null | awk '$1 == "port" {print $2}'
		cat /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null |
			awk 'tolower($1) == "port" {print $2}'
		systemctl show ssh.socket -p Listen --value 2>/dev/null |
			tr ' ' '\n' | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p'
	} | grep -x '[0-9][0-9]*' | sort -un | grep . || printf '%s\n' "$SSH_DEFAULT_PORT"
}

dvb_main "$@"
