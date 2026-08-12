# Uninstall Tailscale User Setup

You can remove the Tailscale User Setup files without deleting the local Tailscale node state. Remove the state separately if you want to completely reset the local node identity.

## Stop and disable Tailscale

Stop the per-user daemon and disable it from the systemd user manager:

```sh
systemctl --user disable --now tailscaled.service
```

## Remove the systemd user units

```sh
rm -f \
  "$HOME/.config/systemd/user/tailscaled.service" \
  "$HOME/.config/systemd/user/tailscale-wait-online.service" \
  "$HOME/.config/systemd/user/tailscale-online.target"

systemctl --user daemon-reload
```

## Remove the commands and Tailscale binaries

```sh
rm -f \
  "$HOME/.local/bin/tailscale" \
  "$HOME/.local/bin/tailscaled" \
  "$HOME/.local/share/tailscale/tailscale" \
  "$HOME/.local/share/tailscale/tailscaled"

rmdir "$HOME/.local/share/tailscale" 2>/dev/null || true
```

This removes the installed software but leaves the user configuration and Tailscale state in place.

## Remove the user configuration

If you no longer want to keep your daemon configuration, remove it separately:

```sh
rm -f "$HOME/.config/tailscale/tailscaled.defaults"
rmdir "$HOME/.config/tailscale" 2>/dev/null || true
```

## Remove the local node state

The node state contains the local Tailscale identity and other persistent daemon data. Keep it if you expect to reinstall Tailscale User Setup and want to preserve the same local node identity.

To completely remove the local state:

```sh
rm -rf "$HOME/.local/state/tailscale"
```

Removing the local state is destructive. A later installation will initialize new local state and can appear as a new device in your tailnet.

Removing files from the host does not replace tailnet administration. If you also want to remove the device from your tailnet, delete the device from the Tailscale Machines page in the admin console.

For comparison, refer to the upstream [Uninstall Tailscale](https://tailscale.com/docs/features/client/uninstall) documentation.

## Disable lingering, if you enabled it for this setup

If you previously enabled systemd lingering specifically so Tailscale would keep running after logout, and no other user service needs it, you can disable it:

```sh
loginctl disable-linger "$USER"
```

Do not disable lingering if other user services rely on your systemd user manager remaining active after logout.

## Related topics

- [Install Tailscale as a user](install.md)
- [Update Tailscale User Setup](update.md)
- [Tailscale User Setup on Linux](user-setup.md)
