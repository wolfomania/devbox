#!/bin/sh
# Headless OpenJDK. MOD_PIN is the major version, e.g. 21.

dvb_check() {
	command -v javac >/dev/null 2>&1 || return 1
	javac -version 2>&1 | awk '{print "jdk", $2}'
}

dvb_install() {
	pkg_install "openjdk-${MOD_PIN}-jdk-headless"
}
