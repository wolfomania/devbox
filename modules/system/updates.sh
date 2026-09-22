#!/bin/sh
# Security updates: unattended-upgrades, installing security patches daily.
#
# apt-daily-upgrade.timer runs once a day, at 06:00 plus up to an hour of
# random delay. Ubuntu's own 50unattended-upgrades decides what is eligible:
# the security pockets only, so Docker's, NodeSource's and every other vendor
# repository stay where they are until upgraded by hand.
#
# Nothing reboots: unattended-upgrades leaves Automatic-Reboot unset, which
# means off. Running processes keep the library they started with, and
# with no terminal to ask needrestart only lists the services that would need a
# restart. A package's own upgrade script may still restart its service, as
# openssh-server does; open SSH sessions survive that. A kernel patch takes
# effect at the next reboot, which /var/run/reboot-required announces.
#
#   modules/system/updates.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

# Sorts after Ubuntu's 20auto-upgrades, so these values win over it.
readonly UPDATES_CONF=/etc/apt/apt.conf.d/52devbox-updates

dvb_check() {
	pkg_installed unattended-upgrades || return 1
	apt-config dump 2>/dev/null | grep -qx 'APT::Periodic::Unattended-Upgrade "1";' || return 1
	printf 'unattended-upgrades %s\n' "$(pkg_version unattended-upgrades)"
}

dvb_install() {
	pkg_install unattended-upgrades || return 1

	as_root tee "$UPDATES_CONF" > /dev/null <<'CONF' || return 1
// Managed by devbox: security patches daily.
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF

	# A container has no systemd to run the timers; the setting is still
	# in place for the box it becomes.
	if [ -d /run/systemd/system ]; then
		as_root systemctl enable --now apt-daily.timer apt-daily-upgrade.timer > /dev/null 2>&1 || return 1
	fi
	log_dim "  security patches install daily; reboots are left to you"
}

dvb_main "$@"
