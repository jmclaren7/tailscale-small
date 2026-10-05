#!/bin/sh
#
# Runs inside an x86_64 OpenWrt rootfs container (see test-packages.sh) and
# checks the package lifecycle with the system's own package manager.
#
# Usage: test-install.sh ipk|apk PKGVER
#   Packages are read from /pkgs, the smoke test from /scripts.

set -eu

fmt=$1
pkgver=$2

mkdir -p /var/lock /var/run /tmp/run

if [ "$fmt" = ipk ]; then
	pkg_install() { opkg install "$@"; }
	pkg_reinstall() { opkg install --force-reinstall "$@"; }
	pkg_remove() { opkg remove "$@"; }
else
	pkg_install() { apk add --no-network --allow-untrusted "$@"; }
	pkg_reinstall() { apk add --no-network --allow-untrusted "$@"; }
	pkg_remove() { apk del --no-network "$@"; }
fi

# The files are named like the AIO binaries; the packages are tailscale-small
# and tailscale-small-upx.
plain=/pkgs/tailscale-small-aio_${pkgver}_x86_64.$fmt
upx=/pkgs/tailscale-small-aio-upx_${pkgver}_x86_64.$fmt
wrong_arch=/pkgs/tailscale-small-aio_${pkgver}_mipsel.$fmt

step() { printf '\n### %s\n' "$*"; }
fail() { echo "FAIL: $*"; exit 1; }

# kmod-tun can't be installed in a container (no kernel), so a dummy package
# satisfies the dependency.
step "install dummy kmod-tun"
pkg_install /pkgs/kmod-tun.$fmt

step "reject a package built for another architecture"
if pkg_install "$wrong_arch" > /tmp/out 2>&1; then
	cat /tmp/out
	fail "installing the mipsel package on x86_64 reported success"
fi
cat /tmp/out
grep -q "this package is for mipsel_\* devices" /tmp/out || fail "no architecture error message"
if [ "$fmt" = ipk ]; then
	[ ! -e /usr/sbin/tailscaled ] || fail "files were installed anyway"
else
	# apk installs it despite the failed pre-install; the service must stay off.
	grep -q "apk del tailscale-small" /tmp/out || fail "no removal hint"
	! ls /etc/rc.d | grep -q tailscale || fail "service was enabled for the wrong architecture"
	pkg_remove tailscale-small
fi

for pkg in "$plain" "$upx"; do
	if [ "$pkg" = "$plain" ]; then
		name=tailscale-small other=$upx
	else
		name=tailscale-small-upx other=$plain
	fi

	step "install $name"
	pkg_install "$pkg"
	[ -x /usr/sbin/tailscaled ] || fail "/usr/sbin/tailscaled missing"
	[ "$(readlink /usr/sbin/tailscale)" = tailscaled ] || fail "/usr/sbin/tailscale symlink missing"
	[ -f /etc/config/tailscale ] || fail "/etc/config/tailscale missing"
	grep -qx /etc/tailscale/ "/lib/upgrade/keep.d/$name" || fail "state directory not kept on sysupgrade"
	ls /etc/rc.d | grep -q '^S80tailscale$' || fail "init script was not enabled"
	tailscale version

	step "$name conflicts with the other variant"
	if pkg_install "$other" > /tmp/out 2>&1; then
		cat /tmp/out
		fail "both variants installed at once"
	fi
	cat /tmp/out

	step "reinstall $name"
	pkg_reinstall "$pkg"
	[ -x /usr/sbin/tailscaled ] || fail "/usr/sbin/tailscaled missing after reinstall"

	step "$name: tailscale up starts a login (nftables firewall mode)"
	TS_DEBUG_FIREWALL_MODE=nftables sh /scripts/smoke-test.sh /usr/sbin/tailscaled /usr/sbin/tailscale

	step "remove $name"
	pkg_remove "$name"
	[ ! -e /usr/sbin/tailscaled ] || fail "/usr/sbin/tailscaled left behind"
	[ ! -e /usr/sbin/tailscale ] || fail "/usr/sbin/tailscale left behind"
	! ls /etc/rc.d | grep -q tailscale || fail "init script link left behind"
	rm -f /etc/config/tailscale*
done

printf '\nPASS: %s packages\n' "$fmt"
