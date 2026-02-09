# tailscale-small

Automatically builds [Tailscale](https://github.com/tailscale/tailscale) binaries with flags for space or memory constrained devices like routers running OpenWrt.

## What is this?

This repository automatically builds `tailscale` and `tailscaled` binaries from the official Tailscale repository using the custom `build_custom.sh` script from this repository. The custom flags are called using a new `--small` and `--smallaio` build script option.

Using the --extra-small option in the tailscale build script can cause problems, this project aims to provide binaries that will work as easily as the full size ones.

Some OpenWRT devices are space constrained, memory constrained or both. For memory constrained devices you might prefer the seperate `tailscale` and `tailscald` binaries. For space constrained systems you will definitly want to use `tailscald-aio` (name it tailscaled and create a symlink to it named tailscale). 

## Supported Platforms

- **linux/amd64** - x86-64 Linux systems
- **linux/arm64** - ARM64/aarch64 Linux systems  
- **linux/ramips** - MIPS little-endian (commonly used in routers / OpenWRT)

## Releases

New releases are automatically created when Tailscale publishes a new version. The workflow checks for new releases every 12 hours and builds the binaries automatically.

Each release contains:

- `tailscale-linux-amd64` / `tailscaled-linux-amd64` / `tailscaled-aio-linux-amd64` 
- `tailscale-linux-arm64` / `tailscaled-linux-arm64` / `tailscaled-aio-linux-arm64`
- `tailscale-linux-ramips` / `tailscaled-linux-ramips` / `tailscaled-aio-linux-ramips`

## Manual Build

You can manually use this build script:

1. Clone tailscale/tailscale and copy build_custom.sh from this repository
2. `GOOS=linux GOARCH=arm64 ./build_custom.sh --small ./cmd/tailscale`
3. `GOOS=linux GOARCH=arm64 ./build_custom.sh --small ./cmd/tailscaled`
4. Optionally: `GOOS=linux GOARCH=arm64 ./build_custom.sh --small ./cmd/tailscaled-aio`

## License

This repository contains only build automation. The Tailscale binaries are built from the [official Tailscale repository](https://github.com/tailscale/tailscale) and are subject to Tailscale's BSD 3-Clause License.
