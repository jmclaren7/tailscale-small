#!/usr/bin/env sh
#
# Builds OpenWrt packages around a tailscaled binary built with --smallaio,
# without needing the OpenWrt SDK:
#   .ipk for opkg (OpenWrt 24.10 and older)
#   .apk for apk-tools v3 (OpenWrt 25.12 and newer)
#
# The package contents mirror the official OpenWrt tailscale package
# (/usr/sbin/tailscaled, a tailscale symlink, /etc/init.d/tailscale and
# /etc/config/tailscale) so existing configs keep working.
#
# Go binaries are static and run on every CPU variant of an architecture
# (mipsel_24kc, mipsel_74kc, ...), so one package per CPU family is marked
# arch "all"/"noarch" and its scripts check DISTRIB_ARCH in
# /etc/openwrt_release instead. opkg aborts when that pre-install check fails.
# apk 3 only reports the failure and installs anyway, so its post-install
# repeats the check and then leaves the service disabled.
#
# Usage: build-packages.sh NAME VERSION ARCH_LABEL ARCH_GLOB BINARY OUTDIR
#   NAME        package name: tailscale-small or tailscale-small-upx
#   VERSION     Tailscale version without the leading v, e.g. 1.102.5
#   ARCH_LABEL  arch used in the file names, e.g. mipsel
#   ARCH_GLOB   shell pattern for DISTRIB_ARCH, e.g. 'mipsel_*'
#   BINARY      tailscaled built with --smallaio
#   OUTDIR      directory for the .ipk and .apk files, named like the AIO
#               binaries: tailscale-small-upx is written to
#               tailscale-small-aio-upx_VERSION-r1_ARCH_LABEL.ipk and .apk
#
# Environment:
#   PKG_RELEASE        package release number (default 1)
#   SOURCE_DATE_EPOCH  timestamp for files in the .ipk (default now)
#   APK_IMAGE          container image with apk-tools v3, used through Docker
#                      when `apk mkpkg` isn't available locally

set -eu

if [ "$#" -ne 6 ]; then
	sed -n 's/^# \{0,1\}//; /^Usage/,/^$/p' "$0" >&2
	exit 2
fi

name=$1
version=$2
arch_label=$3
arch_glob=$4
binary=$5
outdir=$6

pkgver="$version-r${PKG_RELEASE:-1}"
mtime=${SOURCE_DATE_EPOCH:-$(date +%s)}
repo=${GITHUB_REPOSITORY:-jmclaren7/tailscale-small}
url="https://github.com/$repo"
maintainer="$repo <$url>"
apk_image=${APK_IMAGE:-public.ecr.aws/docker/library/alpine:3.24}

# The files are named like the AIO release binaries (aio before upx), but the
# installed package keeps its name.
case "$name" in
*-upx)
	other=${name%-upx}
	file=$other-aio-upx
	;;
*)
	other=$name-upx
	file=$name-aio
	;;
esac

description="Tailscale with a reduced feature set for devices with little flash or RAM. A single tailscaled binary with the tailscale CLI linked to it."
case "$name" in
*-upx) description="$description The binary is UPX-compressed: smaller on flash, but it uses more RAM." ;;
esac

here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$outdir"
outdir=$(cd "$outdir" && pwd)
pkgfile="$outdir/${file}_${pkgver}_${arch_label}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Package contents.
root="$work/root"
install -d "$root/usr/sbin" "$root/etc/init.d" "$root/etc/config"
install -m 0755 "$binary" "$root/usr/sbin/tailscaled"
ln -s tailscaled "$root/usr/sbin/tailscale"
install -m 0755 "$here/files/tailscale.init" "$root/etc/init.d/tailscale"
install -m 0644 "$here/files/tailscale.conf" "$root/etc/config/tailscale"

# As in OpenWrt's package-pack.mk: config files are conffiles, and entries
# that aren't files in the package (the state directory) go in keep.d so
# sysupgrade preserves them and the device stays logged in.
install -d "$root/lib/upgrade/keep.d"
echo "/etc/tailscale/" > "$root/lib/upgrade/keep.d/$name"
conffiles="/etc/config/tailscale
/etc/tailscale/"

# Shell code that exits 1 when the device's CPU architecture doesn't match,
# after printing why and the given hint.
arch_check() { # HINT
	cat <<EOF
arch=\$(sed -n "s/^DISTRIB_ARCH='\\(.*\\)'\$/\\1/p" "\${IPKG_INSTROOT}/etc/openwrt_release" 2>/dev/null)
case "\$arch" in
$arch_glob) ;;
*)
	echo "$name: this package is for $arch_glob devices, but this device is \${arch:-not OpenWrt}." >&2
	echo "$1" >&2
	exit 1
	;;
esac
EOF
}
download_hint="Download the package that matches your device from $url/releases"

tar_gz() { # DIR OUTPUT [FILES...]
	dir=$1
	out=$2
	shift 2
	[ "$#" -gt 0 ] || set -- .
	tar -C "$dir" --format=gnu --numeric-owner --owner=0 --group=0 --sort=name \
		--mtime="@$mtime" -cf - "$@" | gzip -9n > "$out"
}

# .ipk: a gzipped tar of debian-binary, control.tar.gz and data.tar.gz, as
# written by OpenWrt's scripts/ipkg-build.
build_ipk() {
	ipk="$work/ipk"
	control="$ipk/control"
	mkdir -p "$control"

	tar_gz "$root" "$ipk/data.tar.gz"
	installed_size=$(gzip -dc "$ipk/data.tar.gz" | wc -c | tr -d ' ')

	cat > "$control/control" <<EOF
Package: $name
Version: $pkgver
Depends: ca-bundle, kmod-tun
Provides: tailscale, tailscaled
Conflicts: tailscale, $other
Source: $url
SourceName: $name
License: BSD-3-Clause
Section: net
URL: $url
Maintainer: $maintainer
Architecture: all
Installed-Size: $installed_size
Description: $description
EOF
	echo "/etc/config/tailscale" > "$control/conffiles"

	{
		echo "#!/bin/sh"
		echo '[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0'
		arch_check "$download_hint"
	} > "$control/preinst"
	cat > "$control/postinst" <<'EOF'
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_postinst $0 $@
EOF
	cat > "$control/prerm" <<'EOF'
#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_prerm $0 $@
EOF
	chmod 0755 "$control/preinst" "$control/postinst" "$control/prerm"

	tar_gz "$control" "$ipk/control.tar.gz"
	echo "2.0" > "$ipk/debian-binary"
	tar_gz "$ipk" "$pkgfile.ipk" ./debian-binary ./data.tar.gz ./control.tar.gz
}

# .apk: built with `apk mkpkg`, with the same metadata files and maintainer
# scripts as OpenWrt's include/package-pack.mk.
build_apk() {
	aroot="$work/apk-root"
	scripts="$work/apk-scripts"
	cp -a "$root" "$aroot"
	mkdir -p "$aroot/lib/apk/packages" "$scripts"

	meta="$aroot/lib/apk/packages/$name"
	(cd "$root" && find . -type f -o -type l) | sed 's|^\.||' | LC_ALL=C sort > "$meta.list"
	echo "$conffiles" > "$meta.conffiles"
	echo "/etc/config/tailscale $(sha256sum "$root/etc/config/tailscale" | cut -d ' ' -f 1)" > "$meta.conffiles_static"

	{ echo "#!/bin/sh"; arch_check "$download_hint"; } > "$scripts/pre-install"
	{ echo "#!/bin/sh"; echo "export PKG_UPGRADE=1"; arch_check "$download_hint"; } > "$scripts/pre-upgrade"
	{
		echo "#!/bin/sh"
		echo '[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0'
		arch_check "Not enabling the tailscale service. Remove this package with: apk del $name"
		cat <<EOF
[ -s \${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. \${IPKG_INSTROOT}/lib/functions.sh
export root="\${IPKG_INSTROOT}"
export pkgname="$name"
add_group_and_user
default_postinst
EOF
	} > "$scripts/post-install"
	{ echo "#!/bin/sh"; echo "export PKG_UPGRADE=1"; sed 1d "$scripts/post-install"; } > "$scripts/post-upgrade"
	cat > "$scripts/pre-deinstall" <<EOF
#!/bin/sh
[ -s \${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. \${IPKG_INSTROOT}/lib/functions.sh
export root="\${IPKG_INSTROOT}"
export pkgname="$name"
default_prerm
EOF
	chmod 0755 "$scripts"/*

	set -- \
		--info "name:$name" \
		--info "version:$pkgver" \
		--info "description:$description" \
		--info "arch:noarch" \
		--info "license:BSD-3-Clause" \
		--info "origin:$name" \
		--info "url:$url" \
		--info "maintainer:$maintainer" \
		--info "provides:tailscale=$pkgver tailscaled=$pkgver" \
		--info "depends:ca-bundle kmod-tun" \
		--script "pre-install:$scripts/pre-install" \
		--script "pre-upgrade:$scripts/pre-upgrade" \
		--script "post-install:$scripts/post-install" \
		--script "post-upgrade:$scripts/post-upgrade" \
		--script "pre-deinstall:$scripts/pre-deinstall"
	apk_out="$pkgfile.apk"

	# apk records file owners as found on disk, so make everything root-owned.
	# Under Docker that happens on a copy, leaving the bind mount untouched.
	if [ "$(id -u)" = 0 ] && apk mkpkg --help 2>/dev/null | grep -q -- --files; then
		chown -R 0:0 "$aroot"
		apk mkpkg "$@" --files "$aroot" --output "$apk_out"
	else
		docker run --rm -v "$work:$work" -v "$outdir:$outdir" "$apk_image" sh -euc '
			out=$1
			cp -a "$2" /pkgroot
			chown -R 0:0 /pkgroot
			shift 2
			apk mkpkg "$@" --files /pkgroot --output "$out"
			chmod 0644 "$out"
		' sh "$apk_out" "$aroot" "$@"
	fi
}

build_ipk
build_apk
ls -l "$pkgfile".*
