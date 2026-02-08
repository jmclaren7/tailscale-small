# tailscale-small

Automatically builds [Tailscale](https://github.com/tailscale/tailscale) binaries with the `--extra-small` flag for embedded devices and space-constrained systems.

## What is this?

This repository automatically builds `tailscale` and `tailscaled` binaries from the official Tailscale repository using the `--extra-small` build flag, which produces smaller binaries suitable for embedded devices like routers running OpenWrt.

## Supported Platforms

- **linux/amd64** - x86-64 Linux systems
- **linux/arm64** - ARM64/aarch64 Linux systems  
- **linux/ramips** - MIPS little-endian (commonly used in routers)

## Releases

New releases are automatically created when Tailscale publishes a new version. The workflow checks for new releases every 6 hours and builds the binaries automatically.

Each release contains:
- `tailscale-linux-amd64` / `tailscaled-linux-amd64`
- `tailscale-linux-arm64` / `tailscaled-linux-arm64`
- `tailscale-linux-ramips` / `tailscaled-linux-ramips`

## How it works

A GitHub Actions workflow:
1. Checks for new Tailscale releases every 6 hours
2. Clones the official Tailscale repository at the release tag
3. Builds binaries using `build_dist.sh --extra-small` for each platform
4. Creates a GitHub release with all binaries attached

## Manual Trigger

You can manually trigger a build for a specific Tailscale version:
1. Go to the Actions tab
2. Select "Build Tailscale Small" workflow
3. Click "Run workflow"
4. Enter the version tag (e.g., `v1.58.2`)

## License

This repository contains only build automation. The Tailscale binaries are built from the [official Tailscale repository](https://github.com/tailscale/tailscale) and are subject to Tailscale's BSD 3-Clause License.