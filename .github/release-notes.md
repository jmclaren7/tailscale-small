Tailscale [${TAG}](https://github.com/tailscale/tailscale/releases/tag/${TAG}) built with `build_custom.sh --small` and `--smallaio`. See the [README](https://github.com/${REPOSITORY}#readme) for what is included.

### OpenWrt packages

Find your device's architecture with `grep DISTRIB_ARCH /etc/openwrt_release`, then pick the matching file:

| DISTRIB_ARCH | Package files |
|---|---|
| `x86_64` | `*_x86_64.ipk` / `*_x86_64.apk` |
| `aarch64_*` | `*_aarch64.ipk` / `*_aarch64.apk` |
| `arm_cortex-a*` | `*_armv7.ipk` / `*_armv7.apk` |
| `mipsel_*` | `*_mipsel.ipk` / `*_mipsel.apk` |
| `mips_*` | `*_mips.ipk` / `*_mips.apk` |

- `tailscale-small` is the uncompressed binary. `tailscale-small-upx` is UPX-compressed: it takes less flash but more RAM.
- OpenWrt 24.10 and older (opkg): `opkg update && opkg install ./tailscale-small_${VERSION}-r1_<arch>.ipk`
- OpenWrt 25.12 and newer (apk): `apk update && apk add --allow-untrusted ./tailscale-small_${VERSION}-r1_<arch>.apk`
- Then run `tailscale up`. Remove the official `tailscale` package first if it is installed; your login state in `/etc/tailscale` is kept.

### Binaries

For `linux-amd64`, `linux-arm64`, `linux-armv7`, `linux-mipsle` and `linux-mips-24kc` (MIPS builds are softfloat):

- `tailscaled-*` and `tailscale-*`: separate daemon and CLI, best for low-RAM devices.
- `tailscaled-*-aio`: the daemon with the CLI built in, best for low-storage devices. Rename it to `tailscaled` and create a symlink named `tailscale` pointing to it.
- `*-upx`: UPX-compressed versions of the above.

Checksums are in `SHA256SUMS`.
