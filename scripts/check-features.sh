#!/usr/bin/env sh
#
# Fails if the --small / --smallaio builds would omit a Tailscale feature that
# is not listed in omitted-features.txt, so that features added by a new
# Tailscale release are reviewed instead of silently left out.
#
# Run from the root of a tailscale/tailscale checkout:
#   sh /path/to/scripts/check-features.sh /path/to/build_custom.sh /path/to/omitted-features.txt

set -eu

build_script=$1
reviewed_list=$2

features=$(sed -n 's/^SMALL_FEATURES="\(.*\)"$/\1/p' "$build_script")
if [ -z "$features" ]; then
	echo "SMALL_FEATURES not found in $build_script" >&2
	exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

GOOS= GOARCH= go run ./cmd/featuretags --list > "$tmp/list"
GOOS= GOARCH= go run ./cmd/featuretags --min --add="$features,cli" |
	tr ',' '\n' | sed -n 's/^ts_omit_//p' | sort -u > "$tmp/omitted"
sed 's/#.*//' "$reviewed_list" | awk 'NF { print $1 }' | sort -u > "$tmp/reviewed"

comm -23 "$tmp/omitted" "$tmp/reviewed" > "$tmp/new"
comm -13 "$tmp/omitted" "$tmp/reviewed" > "$tmp/stale"

if [ -s "$tmp/stale" ]; then
	for f in $(cat "$tmp/stale"); do
		msg="omitted-features.txt lists \"$f\", which this Tailscale version no longer omits (removed upstream or now included); it can be deleted"
		if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::warning::$msg"; else echo "warning: $msg"; fi
	done
fi

if [ -s "$tmp/new" ]; then
	echo "These Tailscale features would be omitted from the small builds but have not been reviewed:"
	for f in $(cat "$tmp/new"); do
		grep -E "^ *$f:" "$tmp/list" || echo "  $f"
		if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::error::Unreviewed Tailscale feature \"$f\" would be omitted from the small builds"; fi
	done
	echo
	echo "Add each one to SMALL_FEATURES in build_custom.sh if the binary needs it,"
	echo "otherwise list it in omitted-features.txt with a short reason."
	exit 1
fi

echo "All $(wc -l < "$tmp/omitted") omitted features have been reviewed."
