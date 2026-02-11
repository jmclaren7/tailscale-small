# Tailscale-Small

This repository automatically builds [Tailscale](https://github.com/tailscale/tailscale) using the custom `build_custom.sh`. The script uses a set chosen set of build flags to reduce the size of tailscale for low spec devices (like OpenWRT) which are limited by storage, memory or both.

Using the --extra-small option in the tailscale build script can cause problems, this project aims to provide binaries that will work as easily as the full size ones and with all the core features. 

## Platforms

- **linux-amd64** - x86-64 Linux systems
- **linux-arm64** - ARM64/aarch64 Linux systems  
- **linux-ramips** - MIPS little-endian (commonly used in routers / OpenWRT)
- **linux-mips-24kc** - MIPS big-endian softfloat (Atheros/Qualcomm routers / OpenWRT)

## Variations

- Reduced Features Only: Best for memory constrained systems, try the seperate `tailscale` and `tailscaled` binaries. 
- Reduced Features & Combined/AIO: Best for space constrained systems, try `tailscaled-aio`. Rename it to `tailscaled` and then create a symlink named `tailscale`.
- Compressed: The two variations above also have compressed (UPX) versions available with `*-upx` in the name.

## Build Script

The new flags are:

- `--small` reduced size, seperate binaries
- `--smallaio` same as --small but with the client CLI added to `tailscaled` (requires symlink)

## Manual Build

You can manually use this build script:

1. Clone tailscale/tailscale and copy build_custom.sh from this repository
2. `GOOS=linux GOARCH=arm64 ./build_custom.sh --small ./cmd/tailscale`
3. `GOOS=linux GOARCH=arm64 ./build_custom.sh --small ./cmd/tailscaled`
4. Or the combined version: `GOOS=linux GOARCH=arm64 ./build_custom.sh --small ./cmd/tailscaled-aio`

## License

This repository contains only build automation. The Tailscale binaries are built from the [official Tailscale repository](https://github.com/tailscale/tailscale) and are subject to Tailscale's BSD 3-Clause License.
