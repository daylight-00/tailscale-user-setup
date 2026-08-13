# Update Tailscale User Setup

Update Tailscale User Setup by running the installer again. The installer replaces the managed Tailscale binaries and setup files while preserving the user configuration and Tailscale node state.

Tailscale User Setup does not maintain its own version manager or versioned installation tree.

## Update to the latest stable version

Run the installer again:

```sh
curl -fsSL https://raw.githubusercontent.com/daylight-00/tailscale-user-setup/main/install.sh | sh
```

The installer resolves the latest Tailscale version from the stable Tailscale package track, verifies the official static binary archive, updates the managed setup files, and restarts the user daemon.

Check the installed Tailscale version:

```sh
tailscale version
```

## Update to a specific version

Set `TAILSCALE_VERSION` to select an upstream Tailscale version explicitly:

```sh
curl -fsSL https://raw.githubusercontent.com/daylight-00/tailscale-user-setup/main/install.sh \
  | TAILSCALE_VERSION=1.102.2 sh
```

The same mechanism can be used to install an older version if you need to roll back the Tailscale binary payload.

## Update from the unstable track

To install the latest upstream unstable build:

```sh
curl -fsSL https://raw.githubusercontent.com/daylight-00/tailscale-user-setup/main/install.sh \
  | TRACK=unstable sh
```

To return to the stable track, run the installer again without `TRACK=unstable`.

For information about upstream release tracks, refer to [Install unstable Tailscale clients](https://tailscale.com/docs/install/unstable).

## What the installer updates

The installer manages these files:

```text
~/.local/share/tailscale/tailscale
~/.local/share/tailscale/tailscaled
~/.local/bin/tailscale
~/.local/bin/tailscaled
~/.config/systemd/user/tailscaled.service
~/.config/systemd/user/tailscale-wait-online.service
~/.config/systemd/user/tailscale-online.target
```

The `tailscaled` command is a symbolic link to the managed daemon binary.

The installer preserves an existing user configuration file:

```text
~/.config/tailscale/tailscaled.defaults
```

It also preserves the daemon state under:

```text
~/.local/state/tailscale
```

As a result, updating the setup does not intentionally create a new Tailscale node identity.

If you use the [shared-home configuration](install.md#use-a-shared-home-directory), the installer preserves its systemd drop-in. The binaries and base units are shared across the participating hosts, but the installer restarts only the host where it runs. Reload and restart the user service on each other active host after an update:

```sh
systemctl --user daemon-reload
systemctl --user restart tailscaled.service
```

## About `tailscale update`

Tailscale User Setup uses its own installer as the supported update path. Use the commands in this document instead of relying on `tailscale update` to manage this per-user filesystem layout and systemd user service.

The `tailscale update` command remains part of the upstream Tailscale CLI; refer to [Install Tailscale](https://tailscale.com/docs/install) for upstream update options.

## Related topics

- [Install Tailscale as a user](install.md)
- [Uninstall Tailscale User Setup](uninstall.md)
- [Tailscale User Setup on Linux](user-setup.md)
