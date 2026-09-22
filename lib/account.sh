#!/bin/sh
# The account a box is provisioned for.
#
# Run as root, devbox installs into one dedicated login account rather than
# into root or whichever cloud user happened to call sudo. The account gets a
# home, bash, passwordless sudo and the SSH keys that already reach the box,
# so `ssh exclave@box` works as soon as the install is done.
#
# An account that already exists is kept and brought up to that profile: its
# shell, home, sudo rule and keys are checked and fixed where they fall short.
# Only a system account (uid below 1000) is refused, because turning a daemon's
# identity into a login would be a surprise nobody asked for.

ACCOUNT_NAME="${DVB_ACCOUNT:-exclave}"
# useradd's own rule, minus the dot: sudo skips a sudoers.d file named with one.
case "$ACCOUNT_NAME" in
	'' | [!a-z_]* | *[!a-z0-9_-]*)
		printf 'devbox: DVB_ACCOUNT=%s is not a usable account name\n' "$ACCOUNT_NAME" >&2
		exit 1
		;;
esac
ACCOUNT_SUDOERS="/etc/sudoers.d/90-devbox-$ACCOUNT_NAME"
readonly ACCOUNT_MIN_UID=1000

account_exists() { getent passwd "$ACCOUNT_NAME" >/dev/null 2>&1; }

account_field() { getent passwd "$ACCOUNT_NAME" 2>/dev/null | cut -d: -f"$1"; }

# Where the account's home is, or will be once it is created.
account_home() {
	home="$(account_field 6)"
	printf '%s\n' "${home:-/home/$ACCOUNT_NAME}"
}

# Create the account, or bring an existing one up to the profile above.
# Root only; install.sh calls it at the start of the install phase, so a
# --list or --dry-run run never touches the passwd database.
account_ensure() {
	[ "$ACCOUNT_NAME" != "root" ] || return 0

	if account_exists; then
		uid="$(account_field 3)"
		[ "$uid" -ge "$ACCOUNT_MIN_UID" ] || {
			log_err "$ACCOUNT_NAME exists as a system account (uid $uid); set DVB_ACCOUNT to another name"
			return 1
		}
		log_dim "  account $ACCOUNT_NAME exists; checking it"
	else
		useradd --create-home --user-group --shell /bin/bash "$ACCOUNT_NAME" || return 1
		log_dim "  created account $ACCOUNT_NAME"
	fi

	account_fix_shell &&
		account_fix_home &&
		account_grant_sudo &&
		account_copy_keys
}

# A login account needs a shell that logs in.
account_fix_shell() {
	case "$(account_field 7)" in
		*/nologin | */false | "")
			usermod --shell /bin/bash "$ACCOUNT_NAME" || return 1
			log_dim "  gave $ACCOUNT_NAME a login shell"
			;;
	esac
}

account_fix_home() {
	home="$(account_home)"
	if [ ! -d "$home" ]; then
		mkdir -p "$home" && cp -rT /etc/skel "$home" && chown -R "$ACCOUNT_NAME:" "$home" &&
			chmod 750 "$home" || return 1
		log_dim "  created $home"
	fi
	chown "$ACCOUNT_NAME:" "$home"
}

# Passwordless sudo, the same rule cloud images give their default user. The
# account has no password to type, since SSH logs it in with a key.
account_grant_sudo() {
	if ! id -nG "$ACCOUNT_NAME" | tr ' ' '\n' | grep -qx sudo; then
		usermod -aG sudo "$ACCOUNT_NAME" || return 1
		log_dim "  added $ACCOUNT_NAME to the sudo group"
	fi

	rule="$ACCOUNT_NAME ALL=(ALL) NOPASSWD:ALL"
	[ "$(cat "$ACCOUNT_SUDOERS" 2>/dev/null)" = "$rule" ] && return 0

	# A sudoers file with a syntax error disables sudo for everyone, so the
	# rule is checked before it is moved into place.
	staged="$(mktemp)"
	printf '%s\n' "$rule" > "$staged"
	if ! visudo -cqf "$staged"; then
		rm -f "$staged"
		log_err "visudo rejected the sudo rule for $ACCOUNT_NAME"
		return 1
	fi
	install -m 0440 -o root -g root "$staged" "$ACCOUNT_SUDOERS" || {
		rm -f "$staged"
		return 1
	}
	rm -f "$staged"
	log_dim "  $ACCOUNT_NAME may use sudo without a password"
}

# Give an account with no keys the ones that already log in to this box: root's,
# and those of the account that ran sudo. An account that has keys keeps
# exactly those, so a key removed from it stays removed on the next run.
account_copy_keys() {
	ssh_dir="$(account_home)/.ssh"
	keys="$ssh_dir/authorized_keys"
	mkdir -p "$ssh_dir" && touch "$keys" || return 1
	if grep -q '[^[:space:]]' "$keys"; then
		chown -R "$ACCOUNT_NAME:" "$ssh_dir" && chmod 700 "$ssh_dir" && chmod 600 "$keys"
		return
	fi

	account_key_lines /root/.ssh/authorized_keys | account_append_keys "$keys"
	if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && [ "$SUDO_USER" != "$ACCOUNT_NAME" ]; then
		sudo_home="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)"
		[ -n "$sudo_home" ] &&
			account_key_lines "$sudo_home/.ssh/authorized_keys" | account_append_keys "$keys"
	fi

	chown -R "$ACCOUNT_NAME:" "$ssh_dir" && chmod 700 "$ssh_dir" && chmod 600 "$keys" || return 1

	if grep -q '[^[:space:]]' "$keys"; then
		log_dim "  $(grep -c '[^[:space:]]' "$keys") SSH key(s) can log in as $ACCOUNT_NAME"
	else
		log_warn "no SSH key can log in as $ACCOUNT_NAME yet; add one to $keys"
	fi
}

# The key lines of an authorized_keys file.
#
# Cloud images put a redirect on root's keys: a command= that prints "Please
# login as the user ubuntu" and hangs up, beside no-port-forwarding, which
# would break the SSH tunnels devbox tells you to use. Such a key keeps only
# its from= limit. Every other key is copied as it is, options and all, since
# an option such as command="rsync --server ..." is what keeps it harmless.
account_key_lines() {
	[ -r "$1" ] || return 0
	grep -v '^[[:space:]]*#' "$1" | grep '[^[:space:]]' | awk '
		!match($0, /(^|[[:space:]])(ssh-(rsa|dss|ed25519)|ecdsa-sha2-[^[:space:]]+|sk-[^[:space:]]+)[[:space:]]/) { next }
		{
			options = substr($0, 1, RSTART)
			key = substr($0, RSTART)
			sub(/^[[:space:]]+/, "", key)
		}
		options !~ /command="[^"]*Please login as/ { print; next }
		match(options, /from="[^"]*"/) { print substr(options, RSTART, RLENGTH) " " key; next }
		{ print key }
	'
}

# Append each key line from stdin unless its key is already in the file.
account_append_keys() {
	while IFS= read -r line; do
		blob="$(printf '%s\n' "$line" | awk '{for (i = 1; i < NF; i++) if ($i ~ /^(ssh-|ecdsa-|sk-)/) {print $(i + 1); exit}}')"
		[ -n "$blob" ] || continue
		grep -qF "$blob" "$1" && continue
		printf '%s\n' "$line" >> "$1"
	done
}
