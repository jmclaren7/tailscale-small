#!/usr/bin/env sh
#
# Installs the x86_64 packages into OpenWrt rootfs containers with the real
# package managers (opkg on 24.10, apk on 25.12) and runs test-install.sh.
# Needs Docker and /dev/net/tun.
#
# Usage: test-packages.sh PKGDIR VERSION BINARY
#   PKGDIR   directory with the x86_64 packages from build-packages.sh
#   VERSION  Tailscale version without the leading v, e.g. 1.102.5
#   BINARY   the x86_64 tailscaled-aio, used to build a mipsel-labelled
#            package for checking that the wrong architecture is rejected
#
# Environment: OPENWRT_IPK_IMAGE, OPENWRT_APK_IMAGE, APK_IMAGE

set -eu

pkgdir=$(cd "$1" && pwd)
version=$2
binary=$3
pkgver="$version-r${PKG_RELEASE:-1}"
ipk_image=${OPENWRT_IPK_IMAGE:-ghcr.io/openwrt/rootfs:x86-64-24.10.5}
apk_image=${OPENWRT_APK_IMAGE:-ghcr.io/openwrt/rootfs:x86-64-25.12.5}
alpine_image=${APK_IMAGE:-public.ecr.aws/docker/library/alpine:3.24}

here=$(cd "$(dirname "$0")" && pwd)
scripts=$(cd "$here/../scripts" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Dummy kmod-tun packages to satisfy the dependency inside containers.
mkdir -p "$work/ipk/control"
cat > "$work/ipk/control/control" <<EOF
Package: kmod-tun
Version: 0-r0
Architecture: all
Description: test dummy
EOF
echo "2.0" > "$work/ipk/debian-binary"
tar -C "$work/ipk/control" --owner=0 --group=0 -czf "$work/ipk/control.tar.gz" .
mkdir -p "$work/ipk/data"
tar -C "$work/ipk/data" --owner=0 --group=0 -czf "$work/ipk/data.tar.gz" .
tar -C "$work/ipk" --owner=0 --group=0 -czf "$work/kmod-tun.ipk" ./debian-binary ./data.tar.gz ./control.tar.gz

sh "$here/pull-image.sh" "$alpine_image" "$ipk_image" "$apk_image"
docker run --rm -v "$work:/work" "$alpine_image" sh -euc '
	apk mkpkg --info name:kmod-tun --info version:0-r0 --info arch:noarch \
		--info "description:test dummy" --output /work/kmod-tun.apk
	chmod 0644 /work/kmod-tun.apk
'

# An OpenWrt-style resolv.conf, so the result doesn't depend on how Docker
# copies the host's (tailscaled can't start if it looks like systemd-resolved's).
printf 'search lan\nnameserver 127.0.0.1\n' > "$work/resolv.conf"

mkdir -p "$work/pkgs"
cp "$pkgdir"/*_"$pkgver"_x86_64.* "$work/kmod-tun.ipk" "$work/kmod-tun.apk" "$work/pkgs/"
sh "$here/build-packages.sh" tailscale-small "$version" mipsel 'mipsel_*' "$binary" "$work/pkgs" > /dev/null

for fmt in ipk apk; do
	image=$ipk_image
	[ "$fmt" = ipk ] || image=$apk_image
	echo "=== $fmt on $image"
	docker run --rm --cap-add=NET_ADMIN --device=/dev/net/tun \
		-v "$work/resolv.conf:/etc/resolv.conf" \
		-v "$work/pkgs:/pkgs:ro" -v "$scripts:/scripts:ro" -v "$here:/test:ro" \
		"$image" sh /test/test-install.sh "$fmt" "$pkgver"
done
