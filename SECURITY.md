# Security Policy

## Reporting a vulnerability

If you believe you have found a security vulnerability in Tailscale User Setup, please do not disclose exploit details in a public issue.

Use GitHub's private vulnerability reporting for this repository when available. If private reporting is unavailable, open a minimal public issue requesting a private contact channel without including sensitive technical details.

The maintainer intends to review and address confirmed vulnerabilities promptly.

## Scope

Security issues in the integration provided by this project are in scope, including:

- the installer
- the Tailscale CLI wrapper
- the systemd user units and configuration
- update and uninstall behavior

Tailscale User Setup installs and runs official, unmodified Tailscale binaries. Vulnerabilities in Tailscale itself should be reported to Tailscale through its official security reporting process.
