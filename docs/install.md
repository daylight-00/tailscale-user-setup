# Install Tailscale as a user

Tailscale User Setup installs the official Tailscale Linux binaries as a self-contained service for the current user. It does not require root access or a system-wide Tailscale installation.

The setup uses [Tailscale userspace networking](https://tailscale.com/docs/concepts/userspace-networking) and a systemd user service instead of a system service and kernel TUN interface.

## Before you begin

You need:

- Linux
- a regular user account
- a working systemd user manager (`systemctl --user`)
- `curl` or `wget`
- `tar` and `sha256sum`

`~/.local/bin` should be on your `PATH` to use the `tailscale` and `tailscaled` commands normally. If it is not, the installer will tell you how to add it.

Tailscale User Setup stores the node identity under your home directory. Do not use the same home directory as the active Tailscale state for multiple hosts. Shared-home and roaming-home setups are not supported.

## Install with the script

Run the installer as your normal user. Do not use `sudo`.

```sh
curl -fsSL https://raw.githubusercontent.com/daylight-00/tailscale-user-setup/main/install.sh | sh
```

The installer downloads the latest stable Tailscale static binaries from the official Tailscale package server, verifies the published SHA-256 checksum, installs the user setup files, and starts `tailscaled.service` with the systemd user manager.

After installation, connect the device to your tailnet:

```sh
tailscale up
```

The command prints an authentication URL. Open the URL and authenticate the device. For more information about joining a tailnet, refer to the [Tailscale Linux installation guide](https://tailscale.com/docs/install/linux).

### Install a specific Tailscale version

Set `TAILSCALE_VERSION` to install a specific upstream Tailscale version:

```sh
curl -fsSL https://raw.githubusercontent.com/daylight-00/tailscale-user-setup/main/install.sh \
  | TAILSCALE_VERSION=1.102.2 sh
```

The version selects the official Tailscale binary payload only. Tailscale User Setup does not maintain a separate versioned installation tree.

### Install from the unstable track

The stable track is used by default. To install the latest unstable Tailscale build:

```sh
curl -fsSL https://raw.githubusercontent.com/daylight-00/tailscale-user-setup/main/install.sh \
  | TRACK=unstable sh
```

Unstable Tailscale builds are intended for testing. Refer to [Install unstable Tailscale clients](https://tailscale.com/docs/install/unstable) for information about the upstream unstable track.

## Verify the installation

Check that the user service is running:

```sh
systemctl --user status tailscaled.service
```

Check the Tailscale addresses assigned to the device:

```sh
tailscale ip
```

Check the connection status:

```sh
tailscale status
```

Because this setup uses userspace networking, no Tailscale network interface is created in the Linux kernel. Use `tailscale ping` rather than the system `ping` command when testing a tailnet destination from this host.

## Keep Tailscale running after logout

A systemd user manager can stop after the user's last login session ends. If you want Tailscale to remain running while you are logged out, enable lingering for your account:

```sh
loginctl enable-linger "$USER"
```

Whether an unprivileged user can enable lingering depends on the system policy. If the command is not permitted, ask the system administrator to enable lingering for your account.

This setting affects the lifetime of your entire systemd user manager, not only Tailscale.

## Configure a SOCKS5 proxy

Userspace networking does not create a kernel TUN interface, so ordinary applications do not automatically send outbound tailnet traffic through Tailscale. You can expose the userspace network stack as a SOCKS5 proxy when an application needs outbound access to the tailnet.

Edit:

```text
~/.config/tailscale/tailscaled.defaults
```

Set `FLAGS`:

```sh
FLAGS="--socks5-server=localhost:1055"
```

Restart the daemon:

```sh
systemctl --user restart tailscaled.service
```

Applications that support SOCKS5 can then use `localhost:1055`. For example:

```sh
ALL_PROXY=socks5://localhost:1055/ command
```

For more information, refer to [Userspace networking mode](https://tailscale.com/docs/concepts/userspace-networking).

## Manual installation

The install script is a convenience wrapper around the setup described below. You can reproduce the complete user setup manually.

### 1. Download the Tailscale static binaries

Choose a Tailscale version and architecture from the [Tailscale Packages](https://pkgs.tailscale.com/stable/#static) page.

For example:

```sh
VERSION=1.102.2
ARCH=amd64
curl -fLO "https://pkgs.tailscale.com/stable/tailscale_${VERSION}_${ARCH}.tgz"
curl -fLO "https://pkgs.tailscale.com/stable/tailscale_${VERSION}_${ARCH}.tgz.sha256"
sha256sum -c "tailscale_${VERSION}_${ARCH}.tgz.sha256"
tar -xzf "tailscale_${VERSION}_${ARCH}.tgz"
```

The examples below assume the extracted directory is:

```text
tailscale_${VERSION}_${ARCH}/
```

### 2. Create the user directories

```sh
mkdir -p \
  "$HOME/.local/bin" \
  "$HOME/.local/share/tailscale" \
  "$HOME/.local/state/tailscale" \
  "$HOME/.config/tailscale" \
  "$HOME/.config/systemd/user"

chmod 0700 "$HOME/.local/state/tailscale"
```

### 3. Install the Tailscale binaries

Keep the upstream binaries unmodified under the application data directory:

```sh
install -m 0755 "tailscale_${VERSION}_${ARCH}/tailscale" \
  "$HOME/.local/share/tailscale/tailscale"

install -m 0755 "tailscale_${VERSION}_${ARCH}/tailscaled" \
  "$HOME/.local/share/tailscale/tailscaled"
```

Expose `tailscaled` as a normal user command:

```sh
ln -sfn ../share/tailscale/tailscaled "$HOME/.local/bin/tailscaled"
```

### 4. Install the Tailscale CLI wrapper

The wrapper points the normal `tailscale` CLI at the per-user LocalAPI socket.

```sh
curl -fsSL \
  https://raw.githubusercontent.com/daylight-00/tailscale-user-setup/main/bin/tailscale \
  -o "$HOME/.local/bin/tailscale"
chmod 0755 "$HOME/.local/bin/tailscale"
```

### 5. Install the daemon configuration

```sh
curl -fsSL \
  https://raw.githubusercontent.com/daylight-00/tailscale-user-setup/main/systemd/tailscaled.defaults \
  -o "$HOME/.config/tailscale/tailscaled.defaults"
```

The default configuration listens for Tailscale UDP traffic on port `41641` and leaves additional `tailscaled` flags empty.

### 6. Install the systemd user units

```sh
for file in \
  tailscaled.service \
  tailscale-wait-online.service \
  tailscale-online.target
do
  curl -fsSL \
    "https://raw.githubusercontent.com/daylight-00/tailscale-user-setup/main/systemd/$file" \
    -o "$HOME/.config/systemd/user/$file"
done
```

Reload the user manager and start Tailscale:

```sh
systemctl --user daemon-reload
systemctl --user enable --now tailscaled.service
```

### 7. Connect to your tailnet

Make sure `~/.local/bin` is on your `PATH`, then run:

```sh
tailscale up
```

If it is not yet on your `PATH`, you can run the wrapper directly:

```sh
~/.local/bin/tailscale up
```

## Troubleshooting

Check the service status:

```sh
systemctl --user status tailscaled.service
```

View daemon logs from the user journal:

```sh
journalctl --user -u tailscaled.service -e
```

Confirm which CLI your shell resolves:

```sh
command -v tailscale
```

For Tailscale-specific diagnostics, refer to the [Tailscale troubleshooting documentation](https://tailscale.com/docs/reference/troubleshooting).

## Related topics

- [Update Tailscale User Setup](update.md)
- [Uninstall Tailscale User Setup](uninstall.md)
- [Tailscale User Setup on Linux](user-setup.md)
- [Install Tailscale on Linux](https://tailscale.com/docs/install/linux)
- [Userspace networking mode](https://tailscale.com/docs/concepts/userspace-networking)
