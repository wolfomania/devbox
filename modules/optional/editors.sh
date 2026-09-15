#!/bin/sh
# Neovim with no configuration imposed; ~/.config/nvim is left untouched.

dvb_check() {
	command -v nvim >/dev/null 2>&1 || return 1
	nvim --version 2>/dev/null | head -1 | awk '{print "nvim", substr($2, 2)}'
}

dvb_install() {
	pkg_install neovim
}
