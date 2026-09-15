#!/bin/sh
# TeX Live from apt. The packages below are the manually-marked set; apt pulls
# the rest in as dependencies.
#
#   modules/optional/latex.sh check | install | version
. "$(dirname -- "$0")/../../lib/module.sh"

LATEX_PACKAGES="texlive-latex-base texlive-latex-recommended texlive-latex-extra
texlive-fonts-recommended texlive-fonts-extra texlive-lang-english latexmk"

dvb_check() {
	command -v pdflatex >/dev/null 2>&1 || return 1
	# The full banner is "pdfTeX 3.14159265-2.6-1.40.25 (TeX Live 2023/Debian)";
	# the TeX Live year is the part anyone actually recognises.
	pdflatex --version 2>/dev/null | head -1 | sed -n 's/.*(\(TeX Live [0-9]*\).*/\1/p'
}

dvb_install() {
	# shellcheck disable=SC2086
	pkg_install $LATEX_PACKAGES
}

dvb_main "$@"
