# Tailscale-Small

This repository automatically builds [Tailscale](https://github.com/tailscale/tailscale) using the custom `build_custom.sh`. The script uses a chosen set of build flags to reduce the size of Tailscale for low-spec devices (like OpenWrt routers) that are limited by storage, memory or both.

Using the `--extra-small` option in Tailscale's build script can cause problems. This project aims to provide binaries that work as easily as the full-size ones, with all the core features. A workflow checks for new Tailscale releases every 12 hours and publishes binaries and OpenWrt packages to [Releases](../../releases).

## Platforms

| Binaries | CPU | OpenWrt arch (`DISTRIB_ARCH`) | OpenWrt package suffix |
|---|---|---|---|
| `linux-amd64` | x86-64 | `x86_64` | `_x86_64` |
| `linux-arm64` | ARM64 / aarch64 | `aarch64_*` | `_aarch64` |
| `linux-armv7` | 32-bit ARMv7 (softfloat, so it also runs on chips without an FPU) | `arm_cortex-a*` | `_armv7` |
| `linux-mipsle` | MIPS little-endian softfloat (ramips MT7621/MT76x8 and most other MIPS routers) | `mipsel_*` | `_mipsel` |
| `linux-mips-24kc` | MIPS big-endian softfloat (Atheros/Qualcomm ath79) | `mips_*` | `_mips` |

## Variations

- Reduced features only: best for memory-constrained systems. Use the separate `tailscale` and `tailscaled` binaries.
- Reduced features and combined (AIO): best for space-constrained systems. Use `tailscaled-<platform>-aio`, rename it to `tailscaled` and create a symlink named `tailscale` pointing to it.
- Compressed: both variations above also come UPX-compressed, with `-upx` in the name. They take less space but more RAM, because the whole binary is decompressed into memory at startup.

## OpenWrt packages

Each release includes OpenWrt packages built around the AIO binary: `tailscale-small` (uncompressed) and `tailscale-small-upx` (UPX-compressed). They install the same files as the official `tailscale` package (`/usr/sbin/tailscaled`, the `tailscale` symlink, `/etc/init.d/tailscale` and `/etc/config/tailscale`), so existing configs and LuCI apps keep working.

1. Find your architecture with `grep DISTRIB_ARCH /etc/openwrt_release` and download the package with the matching suffix from the table above.
2. Remove the official package if it is installed: `opkg remove tailscale` or `apk del tailscale`. Your login state in `/etc/tailscale` is kept.
3. Install it:
   - OpenWrt 24.10 and older (opkg): `opkg update && opkg install ./tailscale-small_<version>-r1_<arch>.ipk`
   - OpenWrt 25.12 and newer (apk): `apk update && apk add --allow-untrusted ./tailscale-small_<version>-r1_<arch>.apk`
4. Run `tailscale up`.

Notes:

- The packages depend on `kmod-tun` and `ca-bundle`, which the package manager installs from the OpenWrt feeds. That is why `update` runs first.
- `--allow-untrusted` is needed because the `.apk` isn't signed with OpenWrt's key.
- One package covers every CPU variant of an architecture (for example `mipsel_24kc` and `mipsel_74kc`), so packages are marked as architecture-independent and check `DISTRIB_ARCH` during install. opkg refuses a package for the wrong architecture. apk installs it with an error and leaves the service disabled, so remove it again with `apk del`.
- `/etc/tailscale` is kept across sysupgrade, so the device stays logged in.
- To upgrade, install the new package the same way. opkg restarts the service during the upgrade, so if you are connected to the router over Tailscale, run it with `nohup opkg install ... &`. apk leaves the old version running until you run `service tailscale restart`.
- `/etc/config/tailscale` sets the port, state file and firewall mode (`nftables` for firewall4, `iptables` for firewall3), as in the official package.

## Included features

`--small` and `--smallaio` start from Tailscale's minimal build (`featuretags --min`) and add back `SMALL_FEATURES` from `build_custom.sh`:

- `osrouter`, `iptables` (nftables support is always built in), `dns`, `portmapper`, `listenrawdisco`
- `useroutes`, `advertiseroutes`, `useexitnode`, `advertiseexitnode` (subnet routers and exit nodes)
- `unixsocketidentity`
- `ipnbus`: required for `tailscale up` to apply settings and print the login URL
- `bakedroots`: Let's Encrypt root certificates as a fallback when the device has no CA bundle

Everything else is left out on purpose. [omitted-features.txt](omitted-features.txt) lists each omitted feature with a short reason and approximate size.

The binaries are statically linked, so they also run on musl systems like OpenWrt. They support the `direct`, `resolvconf` and `openresolv` ways of managing `/etc/resolv.conf`, which covers OpenWrt and most embedded systems. They don't include systemd-resolved or NetworkManager support, so `tailscaled` fails to start on hosts where one of those manages `/etc/resolv.conf`, such as a default Ubuntu or Fedora install. Use the official Tailscale packages there.

Because the build starts from "nothing", any feature that Tailscale splits out in a future release is dropped automatically. That is what happened in v1.98, when `ipnbus` became optional and `tailscale up` silently stopped working. To prevent a repeat, the workflow:

- fails if a release would omit a feature that isn't listed in `omitted-features.txt` (`scripts/check-features.sh`);
- fails if `SMALL_FEATURES` names a feature that no longer exists (`build_custom.sh`);
- runs every binary (under QEMU for the non-x86 builds) and checks that `tailscale up` starts a login (`scripts/smoke-test.sh`);
- installs the x86_64 packages on OpenWrt 24.10 and 25.12 containers and repeats the login check there (`openwrt/test-packages.sh`).

When the feature check fails after a Tailscale release, add each new feature to `SMALL_FEATURES` if the binary needs it, or to `omitted-features.txt` with a reason.

## Build script

The new flags are:

- `--small`: reduced size, separate binaries
- `--smallaio`: same as `--small` but with the CLI built into `tailscaled` (requires a symlink)

## Manual build

You can use the build script manually from a clone of tailscale/tailscale:

1. Clone tailscale/tailscale and copy `build_custom.sh` from this repository into it.
2. `GOOS=linux GOARCH=arm64 ./build_custom.sh --small ./cmd/tailscale`
3. `GOOS=linux GOARCH=arm64 ./build_custom.sh --small ./cmd/tailscaled`
4. Or build the combined version: `GOOS=linux GOARCH=arm64 ./build_custom.sh --smallaio -o tailscaled-aio ./cmd/tailscaled`

For MIPS routers add `GOMIPS=softfloat`, and for 32-bit ARM use `GOARCH=arm GOARM=7,softfloat`.

To build OpenWrt packages from an AIO binary, run `openwrt/build-packages.sh` (see the usage notes at the top of the script; the `.apk` needs Docker or apk-tools v3).

## License

This repository contains only build automation. The Tailscale binaries are built from the [official Tailscale repository](https://github.com/tailscale/tailscale) and are subject to Tailscale's BSD 3-Clause License. `openwrt/files/tailscale.init` is adapted from the official OpenWrt package and is licensed under Apache-2.0.
