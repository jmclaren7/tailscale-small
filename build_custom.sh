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

${tags:+-echo "Warning! Existing Build Tags: $tags"}

tags="${TAGS:-}"
ldflags="-X tailscale.com/version.longStamp=${VERSION_LONG} -X tailscale.com/version.shortStamp=${VERSION_SHORT}"

# build_dist.sh arguments must precede go build arguments.
while [ "$#" -gt 1 ]; do
	case "$1" in
	--smallaio)
		# --smallaio is the same as --small but it's AIO (CLI support), ideal for low storage devices.
		echo "--smallaio (small AIO binary with CLI support)"
		shift
		ldflags="$ldflags -w -s"
    	tags="${tags:+$tags,}$(GOOS= GOARCH= $go run ./cmd/featuretags --min --add=osrouter,portmapper,dns,useexitnode,advertiseexitnode,useroutes,advertiseroutes,unixsocketidentity,iptables,lazywg,cli)"
    	;;
    --small)
		# --small is a smaller binary but still works with core features for low-spec devices.
		echo "--small (small binary)"
		shift
		ldflags="$ldflags -w -s"
    	tags="${tags:+$tags,}$(GOOS= GOARCH= $go run ./cmd/featuretags --min --add=osrouter,portmapper,dns,useexitnode,advertiseexitnode,useroutes,advertiseroutes,unixsocketidentity,iptables,lazywg)"
    	;;
	--extra-small)
		# --extra-small is a very basic binary that can still route traffic.
		shift
		ldflags="$ldflags -w -s"
		tags="${tags:+$tags,}$(GOOS= GOARCH= $go run ./cmd/featuretags --min --add=osrouter)"
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

exec $go build ${tags:+-tags=$tags} -trimpath -ldflags "$ldflags" "$@"
