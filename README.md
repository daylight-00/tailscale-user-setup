# Tailscale User Setup

Run Tailscale as a complete per-user Linux setup.

Tailscale User Setup maps Tailscale's conventional system-wide Linux setup into a self-contained user-owned layout using the official Tailscale binaries, a systemd user service, and [userspace networking](https://tailscale.com/docs/concepts/userspace-networking). It does not require root access or modify Tailscale itself.

The project defines the setup. The installer is a convenience that automates the same layout documented in the [installation guide](docs/install.md).

## Install

Run the installer as your normal user. Do not use `sudo`.

```sh
curl -fsSL https://raw.githubusercontent.com/daylight-00/tailscale-user-setup/main/install.sh | sh
```

Then connect the device to your tailnet:

```sh
tailscale up
```

The installer downloads the latest stable Tailscale static binaries from the official Tailscale package server, verifies the published SHA-256 checksum, installs the user setup, and starts `tailscaled.service` with the systemd user manager.

For version pinning, the unstable track, manual installation, and post-install options, see [Install Tailscale as a user](docs/install.md).

## What is a user setup?

A conventional Linux Tailscale installation is system-scoped. Tailscale User Setup provides the corresponding components in user scope.

| System setup | User setup |
| --- | --- |
| System filesystem | User-owned filesystem |
| systemd system service | systemd user service |
| `/var/lib/tailscale` | `~/.local/state/tailscale` |
| `/run/tailscale` | User runtime directory |
| Kernel TUN networking | Userspace networking |

The resulting installation keeps the normal `tailscale` and `tailscaled` command names and a persistent Tailscale node identity, while remaining contained within the user account.

For the complete layout and design rationale, see [Tailscale User Setup on Linux](docs/user-setup.md).

## Documentation

- [Install Tailscale as a user](docs/install.md)
- [Update Tailscale User Setup](docs/update.md)
- [Uninstall Tailscale User Setup](docs/uninstall.md)
- [Tailscale User Setup on Linux](docs/user-setup.md)

## Requirements

Tailscale User Setup requires:

- Linux
- a regular user account
- a working systemd user manager (`systemctl --user`)
- `curl` or `wget`
- `tar` and `sha256sum`

`~/.local/bin` should be on your `PATH` to use the installed commands normally. The installer does not modify shell startup files; it prints guidance if the directory is not available through your current `PATH`.

## Differences from a system setup

Tailscale User Setup is complete within user scope, but user scope does not provide the same networking integration as a privileged system installation.

In particular, userspace networking does not create a Tailscale interface in the Linux kernel, so ordinary host applications are not transparently routed to tailnet destinations. Applications that need outbound tailnet access can use the userspace SOCKS5 or HTTP proxy where appropriate.

These differences follow from the user scope rather than from omitted setup components. See [Differences from a system setup](docs/user-setup.md#differences-from-a-system-setup) for details.

## Project status

Tailscale User Setup is an independent community project. It is not affiliated with or maintained by Tailscale Inc.
