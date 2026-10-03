#!/usr/bin/env sh
#
# Checks that a tailscaled + tailscale pair can start a login: tailscaled comes
# up on a TUN device, and `tailscale up` hands it new prefs and waits for the
# login URL. This is what broke when a feature `tailscale up` needs (ipnbus)
# was omitted from the build. Nothing leaves the machine: the login server is
# a closed local port, so `tailscale up` waits until the timeout.
#
# Usage (as root, needs /dev/net/tun): smoke-test.sh TAILSCALED TAILSCALE

set -eu

tailscaled=$1
tailscale=$2

dir=$(mktemp -d)
sock="$dir/tailscaled.sock"
pid=

cleanup() {
	if [ -n "$pid" ]; then
		kill "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	fi
	rm -rf "$dir"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*"
	echo "--- tailscale up output:"
	cat "$dir/up.log" 2>/dev/null || true
	echo "--- tailscaled log:"
	cat "$dir/daemon.log"
	exit 1
}

"$tailscale" version

"$tailscaled" --state="$dir/state" --socket="$sock" --tun="tssmoke$$" --port=0 > "$dir/daemon.log" 2>&1 &
pid=$!

# Plain sh and whole-second sleeps: this also runs on OpenWrt's busybox,
# which has no `timeout` and no fractional `sleep`.
i=0
while [ ! -S "$sock" ]; do
	i=$((i + 1))
	[ "$i" -le 15 ] || fail "tailscaled did not create its socket"
	kill -0 "$pid" 2>/dev/null || fail "tailscaled exited"
	sleep 1
done

"$tailscale" --socket="$sock" status > /dev/null 2>&1 || true

"$tailscale" --socket="$sock" up --login-server=http://127.0.0.1:9 --hostname=smoke-test > "$dir/up.log" 2>&1 &
up_pid=$!
sleep 10
if ! kill -0 "$up_pid" 2>/dev/null; then
	rc=0
	wait "$up_pid" || rc=$?
	fail "tailscale up exited with status $rc instead of waiting for the login URL"
fi
kill "$up_pid" 2>/dev/null || true
wait "$up_pid" 2>/dev/null || true

grep -aq "StartLoginInteractive" "$dir/daemon.log" || fail "tailscaled never started an interactive login"

kill -0 "$pid" 2>/dev/null || fail "tailscaled exited"

echo "PASS: tailscale up applied prefs and started login"
