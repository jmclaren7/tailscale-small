#!/usr/bin/env sh
#
# Runs `go build` with flags configured for binary distribution. All
# it does differently from `go build` is burn git commit and version
# information into the binaries, so that we can track down user
# issues.
#
# If you're packaging Tailscale for a distro, please consider using
# this script, or executing equivalent commands in your
# distro-specific build system.

set -eu

go="go"
if [ -n "${TS_USE_TOOLCHAIN:-}" ]; then
	go="./tool/go"
fi

eval `CGO_ENABLED=0 GOOS=$($go env GOHOSTOS) GOARCH=$($go env GOHOSTARCH) $go run ./cmd/mkversion`

if [ "$#" -ge 1 ] && [ "$1" = "shellvars" ]; then
	cat <<EOF
VERSION_MINOR="$VERSION_MINOR"
VERSION_SHORT="$VERSION_SHORT"
VERSION_LONG="$VERSION_LONG"
VERSION_GIT_HASH="$VERSION_GIT_HASH"
EOF
	exit 0
fi

tags="${TAGS:-}"
ldflags="-X tailscale.com/version.longStamp=${VERSION_LONG} -X tailscale.com/version.shortStamp=${VERSION_SHORT}"

# Features kept by --small and --smallaio. `featuretags --min` omits every
# feature not listed here, including any feature Tailscale adds in a future
# release, so new feature tags need reviewing (see omitted-features.txt).
#   ipnbus:     required for `tailscale up` to apply prefs and start login
#   bakedroots: Let's Encrypt roots as a fallback when the CA bundle is missing
SMALL_FEATURES="osrouter,portmapper,dns,useexitnode,advertiseexitnode,useroutes,advertiseroutes,unixsocketidentity,iptables,listenrawdisco,ipnbus,bakedroots"

# min_tags prints the build tags that omit everything except the given
# features. featuretags ignores unknown names in --add, which would silently
# drop a renamed feature from the build, so check them first.
min_tags() {
	known=$(GOOS= GOARCH= $go run ./cmd/featuretags --list | awk -F: '{gsub(/ /, "", $1); print $1}')
	for f in $(echo "$1" | tr ',' ' '); do
		if ! echo "$known" | grep -qx "$f"; then
			echo "unknown feature \"$f\" (see: go run ./cmd/featuretags --list)" >&2
			exit 1
		fi
	done
	GOOS= GOARCH= $go run ./cmd/featuretags --min --add="$1"
}

# build_dist.sh arguments must precede go build arguments.
while [ "$#" -gt 1 ]; do
	case "$1" in
	--smallaio)
		# --smallaio is the same as --small but it's AIO (CLI support), ideal for low storage devices.
		echo "--smallaio (small AIO binary with CLI support)"
		shift
		ldflags="$ldflags -w -s"
		tags="${tags:+$tags,}$(min_tags "$SMALL_FEATURES,cli")"
		;;
	--small)
		# --small is a smaller binary but still works with core features for low-spec devices.
		echo "--small (small binary)"
		shift
		ldflags="$ldflags -w -s"
		tags="${tags:+$tags,}$(min_tags "$SMALL_FEATURES")"
		;;
	--extra-small)
		# --extra-small is a very basic binary that can still route traffic.
		shift
		ldflags="$ldflags -w -s"
		tags="${tags:+$tags,}$(min_tags osrouter)"
		;;
	--min)
		# --min removes all features even if it results in a useless binary.
		shift
		ldflags="$ldflags -w -s"
		tags="${tags:+$tags,}$(GOOS= GOARCH= $go run ./cmd/featuretags --min)"
		;;
	--box)
		shift
		tags="${tags:+$tags,}ts_include_cli"
		;;
	*)
		break
		;;
	esac
done

echo Build Tags: $tags

# Build static binaries. With cgo, a native build on a glibc host links
# against glibc and fails with "not found" on musl systems such as OpenWrt.
export CGO_ENABLED="${CGO_ENABLED:-0}"

exec $go build ${tags:+-tags=$tags} -trimpath -ldflags "$ldflags" "$@"
