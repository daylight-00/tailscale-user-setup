# Tailscale User Setup on Linux

Tailscale User Setup defines a complete per-user setup for Tailscale on Linux. It maps the conventional system-wide Tailscale installation model into a self-contained user-owned layout using official Tailscale binaries, systemd user services, and Tailscale userspace networking.

The project does not modify or patch Tailscale. The integration layer is limited to filesystem placement, systemd user units, and a small CLI wrapper that selects the per-user LocalAPI socket.

## System setup and user setup

A conventional Linux Tailscale installation is system-scoped: binaries and configuration are installed into system paths, `tailscaled` runs as a system service, persistent state is stored under a system state directory, and Linux normally provides networking through a kernel TUN device.

Tailscale User Setup maps those responsibilities into the current user's scope:

| Responsibility | Conventional system setup | Tailscale User Setup |
| --- | --- | --- |
| CLI command | `/usr/bin/tailscale` | `~/.local/bin/tailscale` |
| Daemon command | `/usr/sbin/tailscaled` | `~/.local/bin/tailscaled` |
| Managed binary payload | system binary directories | `~/.local/share/tailscale/` |
| Daemon configuration | `/etc/default/tailscaled` | `~/.config/tailscale/tailscaled.defaults` |
| Persistent state | `/var/lib/tailscale/` | `~/.local/state/tailscale/` |
| Runtime socket | `/run/tailscale/` | user runtime directory under `tailscale/` |
| Service manager | systemd system manager | systemd user manager |
| Networking backend | kernel TUN on Linux | `--tun=userspace-networking` |

The setup is complete in the sense that each installation responsibility has a user-scoped counterpart. It is not intended to make userspace networking identical to Linux kernel networking.

## Filesystem layout

The installed layout is:

```text
~/.local/
├── bin/
│   ├── tailscale
│   └── tailscaled -> ../share/tailscale/tailscaled
├── share/
│   └── tailscale/
│       ├── tailscale
│       └── tailscaled
└── state/
    └── tailscale/
        └── ...

~/.config/
├── tailscale/
│   └── tailscaled.defaults
└── systemd/
    └── user/
        ├── tailscaled.service
        ├── tailscale-wait-online.service
        └── tailscale-online.target
```

At runtime, the LocalAPI socket is created at:

```text
$XDG_RUNTIME_DIR/tailscale/tailscaled.sock
```

On a typical systemd Linux session, this resolves to:

```text
/run/user/$UID/tailscale/tailscaled.sock
```

### XDG-aligned paths

The setup uses the conventional default locations associated with the XDG base directory model:

- `~/.config` for configuration
- `~/.local/state` for persistent state
- `~/.local/bin` for user commands
- the per-user runtime directory for transient runtime objects

The paths are intentionally fixed to their conventional home-relative defaults rather than following custom `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, or `XDG_STATE_HOME` values. This keeps the systemd units and command layout consistent across supported systemd versions.

The upstream Tailscale binary payload is stored in `~/.local/share/tailscale`, while the public command names are exposed from `~/.local/bin`. Storing executable payloads under `~/.local/share` is not the traditional role of the XDG data directory, so this project describes the layout as **XDG-aligned**, not strictly XDG-compliant.

## Tailscale binaries

The files under:

```text
~/.local/share/tailscale/
```

are the official upstream Tailscale static binaries. Tailscale User Setup does not rebuild, patch, or wrap `tailscaled` itself.

`~/.local/bin/tailscaled` is a symbolic link to the upstream daemon binary so the normal `tailscaled` command remains available in the user's command path.

## Tailscale CLI wrapper

The upstream `tailscale` CLI communicates with `tailscaled` through a LocalAPI socket. A conventional system installation uses the system daemon socket. Tailscale User Setup instead creates a socket in the user's runtime directory.

The `~/.local/bin/tailscale` wrapper runs the unmodified upstream CLI with the appropriate socket argument:

```text
$XDG_RUNTIME_DIR/tailscale/tailscaled.sock
```

The wrapper passes every other command and argument through unchanged. As a result, the user-facing command remains the normal Tailscale CLI:

```sh
tailscale status
tailscale up
tailscale ping <host>
```

There is no separate project-specific CLI.

## systemd user service

`tailscaled.service` runs the daemon with the systemd user manager.

The service starts the official daemon with:

```text
--tun=userspace-networking
--statedir=%h/.local/state/tailscale
--socket=%t/tailscale/tailscaled.sock
```

It also reads:

```text
~/.config/tailscale/tailscaled.defaults
```

for the UDP listen port and additional daemon flags.

The service sets `TS_LOGS_DIR` to the same user state directory so Tailscale daemon state and local log-policy files stay under the persistent state location rather than the application payload directory.

The runtime directory is created by systemd for the user service and is removed with the user runtime environment. Persistent node state remains under `~/.local/state/tailscale`.

The service uses `Type=notify`, `Restart=on-failure`, and `WantedBy=default.target`, mirroring the relevant lifecycle behavior of a normal long-running Tailscale service within the user manager.

The stop cleanup runs with the same `--tun=userspace-networking` backend as the service itself, so it does not attempt cleanup for a kernel Tailscale interface.

### Network ordering

The user service does not copy the system service's dependencies on system network-management units. A systemd user manager cannot usefully order its service against system-manager units such as NetworkManager in the same way a system service can.

`tailscaled` can start before network connectivity is available and observe network changes as connectivity appears. Services that specifically require an online Tailscale node can depend on `tailscale-online.target` instead.

### Coexistence with a system installation

A system-wide Tailscale daemon and a Tailscale User Setup daemon can run on the same host. They use separate persistent state, LocalAPI sockets, and service managers, so they are independent Tailscale node instances.

The per-user `tailscale` wrapper always targets the user daemon. If both installations provide a `tailscale` command, the shell selects the command according to `PATH`.

## Tailscale online target

Tailscale User Setup includes the same readiness model used by upstream Tailscale systemd integration:

```text
tailscale-wait-online.service
tailscale-online.target
```

The wait service executes:

```sh
tailscale wait
```

through the per-user CLI wrapper. A downstream user service that requires Tailscale to be ready should pull in the target and order itself after it:

```ini
[Unit]
Wants=tailscale-online.target
After=tailscale-online.target
```

In userspace networking mode, Tailscale documents that `tailscale wait` waits for `tailscaled` to reach the `Running` state because there is no physical Tailscale network interface. Refer to the [`tailscale wait` CLI reference](https://tailscale.com/docs/reference/tailscale-cli#wait) for the upstream behavior.

## Userspace networking

Userspace networking is the networking backend of the user setup; it is not the user setup itself.

On a conventional Linux installation, Tailscale normally creates a TUN device so the operating system can route application traffic through Tailscale. Creating and configuring that system network interface requires privileges outside a regular user's scope.

Tailscale provides an official alternative:

```text
--tun=userspace-networking
```

In this mode, Tailscale implements networking in-process rather than through a Linux TUN interface. Tailscale documents this mode for environments without access to `/dev/net/tun`, including regular non-root Linux operation and container environments.

For more information, refer to:

- [Userspace networking mode](https://tailscale.com/docs/concepts/userspace-networking)
- [Kernel vs. netstack subnet routing and exit nodes](https://tailscale.com/kb/1177/kernel-vs-userspace-routers)
- [`tailscaled` daemon reference](https://tailscale.com/docs/reference/tailscaled)

## Differences from a system setup

The differences from a conventional system installation follow from the user scope and userspace networking backend. They are not missing installation components.

### No kernel Tailscale interface

The setup does not create a Tailscale TUN interface in the Linux kernel. Commands and applications that depend on a kernel interface therefore behave differently.

For example, use:

```sh
tailscale ping <host>
```

instead of relying on the system `ping` command for a tailnet destination from this host.

### Outbound applications are not transparently routed

Because there is no TUN interface, ordinary host applications do not automatically route outbound traffic to tailnet destinations through Tailscale.

Applications that need outbound tailnet access can use a SOCKS5 or HTTP proxy exposed by the userspace network stack. See [Configure a SOCKS5 proxy](install.md#configure-a-socks5-proxy).

### Userspace routing has different network semantics

For routing features such as subnet routing and exit nodes, Tailscale's userspace netstack operates at TCP/UDP connection level rather than providing the same Layer 3 packet-forwarding behavior as the Linux kernel. Protocol support and performance characteristics can therefore differ from kernel mode.

Refer to [Kernel vs. netstack subnet routing and exit nodes](https://tailscale.com/kb/1177/kernel-vs-userspace-routers) for the upstream comparison.

### Service lifetime is user-scoped

The daemon belongs to the systemd user manager rather than the system manager. On systems where the user manager terminates after the last login session, enable systemd lingering if the node must remain available while the user is logged out.

See [Keep Tailscale running after logout](install.md#keep-tailscale-running-after-logout).

### Shared home directories

The default state directory, `~/.local/state/tailscale`, represents one Tailscale node and must not be used concurrently by multiple hosts.

For controlled shared-home environments such as HPC systems, a systemd drop-in can make both the daemon state and log-policy directory host-specific with the `%H` hostname specifier. The binaries, configuration, and base systemd units remain shared, while each host keeps an independent node identity and runtime socket.

The installer manages the base service file but does not replace service drop-ins, so host-specific state remains configured across updates. Because the binary payload is shared, each active host should reload and restart its user service after the shared installation is updated.

See [Use a shared home directory](install.md#use-a-shared-home-directory).

## Design principles

Tailscale User Setup keeps the integration deliberately small:

- use official Tailscale binaries without modification
- keep the complete setup inside the user's filesystem and user service manager
- use canonical, XDG-aligned home-relative paths
- use the upstream userspace networking backend rather than a custom network implementation
- preserve the normal `tailscale` and `tailscaled` command names
- preserve upstream systemd readiness concepts where they apply to the user manager
- avoid a separate package manager, updater, version tree, or migration framework

The installer automates this layout, but the layout itself is the setup. The complete procedure can be reproduced manually from [Install Tailscale as a user](install.md#manual-installation).

## Related topics

- [Install Tailscale as a user](install.md)
- [Update Tailscale User Setup](update.md)
- [Uninstall Tailscale User Setup](uninstall.md)
- [Install Tailscale on Linux](https://tailscale.com/docs/install/linux)
- [Userspace networking mode](https://tailscale.com/docs/concepts/userspace-networking)
- [`tailscaled` daemon](https://tailscale.com/docs/reference/tailscaled)
