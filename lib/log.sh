#!/bin/sh
# Terminal output helpers. Colour is used only when stdout is a TTY and the
# caller has not set NO_COLOR, so piped output stays clean.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	C_RESET=$(printf '\033[0m')
	C_DIM=$(printf '\033[2m')
	C_BOLD=$(printf '\033[1m')
	C_RED=$(printf '\033[31m')
	C_GREEN=$(printf '\033[32m')
	C_YELLOW=$(printf '\033[33m')
	C_BLUE=$(printf '\033[34m')
else
	C_RESET='' C_DIM='' C_BOLD='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE=''
fi

log_info() { printf '%s\n' "$*"; }
log_dim() { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
log_ok() { printf '%s  ok%s  %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_skip() { printf '%sskip%s  %s\n' "$C_DIM" "$C_RESET" "$*"; }
log_warn() { printf '%swarn%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_err() { printf '%s fail%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

log_step() { printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }

log_head() {
	printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"
	printf '%s%s%s\n' "$C_DIM" "-----------------------------------------------------------" "$C_RESET"
}

die() {
	log_err "$*"
	exit 1
}
