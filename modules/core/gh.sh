#!/bin/sh
# GitHub CLI from the official apt repository, not the distro package.

GH_KEY_URL="https://cli.github.com/packages/githubcli-archive-keyring.gpg"

dvb_check() {
	command -v gh >/dev/null 2>&1 || return 1
	gh --version 2>/dev/null | head -1 | awk '{print $1, $3}'
}

dvb_install() {
	arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
	repo_line="deb [arch=${arch} signed-by=/etc/apt/keyrings/github-cli.gpg] https://cli.github.com/packages stable main"

	pkg_add_repo "github-cli" "$GH_KEY_URL" "$repo_line" || return 1
	pkg_install gh
}
