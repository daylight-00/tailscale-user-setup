#!/bin/sh
# Install Tailscale User Setup for the current Linux user.
#
# Environment variables:
#   TRACK=stable|unstable           Tailscale release track (default: stable)
#   TAILSCALE_VERSION=1.102.2       Pin the upstream Tailscale version

set -eu

REPO="daylight-00/tailscale-user-setup"
TRACK="${TRACK:-stable}"
TAILSCALE_VERSION="${TAILSCALE_VERSION:-}"
RAW_BASE="https://raw.githubusercontent.com/$REPO/main"
PKGS_BASE="https://pkgs.tailscale.com/$TRACK"

say() {
    printf '%s\n' "$*"
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

fetch() {
    url=$1
    output=$2

    if [ "$DOWNLOADER" = curl ]; then
        curl -fsSL "$url" -o "$output"
    else
        wget -q -O "$output" "$url"
    fi
}

cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
    if [ -n "${STAGE_DIR:-}" ] && [ -d "$STAGE_DIR" ]; then
        rm -rf "$STAGE_DIR"
    fi
}

init_paths() {
    DATA_DIR="$HOME/.local/share/tailscale"
    BIN_DIR="$HOME/.local/bin"
    STATE_DIR="$HOME/.local/state/tailscale"
    CONFIG_DIR="$HOME/.config/tailscale"
    UNIT_DIR="$HOME/.config/systemd/user"
    DEFAULTS_FILE="$CONFIG_DIR/tailscaled.defaults"
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)          ARCH=amd64 ;;
        i386|i486|i586|i686)   ARCH=386 ;;
        aarch64|arm64)         ARCH=arm64 ;;
        arm|armv5*|armv6*|armv7*|armv8l)
                               ARCH=arm ;;
        mips)                  ARCH=mips ;;
        mipsel|mipsle)         ARCH=mipsle ;;
        mips64)                ARCH=mips64 ;;
        mips64el|mips64le)     ARCH=mips64le ;;
        riscv64)               ARCH=riscv64 ;;
        *) die "unsupported architecture: $(uname -m)" ;;
    esac
}

check_environment() {
    [ "$(uname -s)" = Linux ] || die "this installer supports Linux only"
    [ -n "${HOME:-}" ] || die "HOME is not set"
    [ -d "$HOME" ] || die "HOME does not exist: $HOME"
    [ "$(id -u)" -ne 0 ] || die "run this installer as a regular user, not root"

    case "$TRACK" in
        stable|unstable) ;;
        *) die "unsupported TRACK: $TRACK" ;;
    esac

    systemctl --user show-environment >/dev/null 2>&1 ||
        die "systemd user manager is unavailable"
}

warn_system_daemon() {
    if systemctl is-active --quiet tailscaled.service 2>/dev/null; then
        warn "system tailscaled.service is active; continuing with a separate per-user daemon"
    fi
}

find_local_repo() {
    LOCAL_REPO=""

    case "$0" in
        */*)
            script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)
            if [ -n "$script_dir" ] &&
               [ -f "$script_dir/systemd/tailscaled.service" ]; then
                LOCAL_REPO=$script_dir
            fi
            ;;
    esac
}

project_file() {
    source_path=$1
    destination=$2
    mode=$3
    temp="$destination.tmp.$$"

    mkdir -p "$(dirname "$destination")"

    if [ -n "$LOCAL_REPO" ]; then
        cp "$LOCAL_REPO/$source_path" "$temp"
    else
        fetch "$RAW_BASE/$source_path" "$temp" ||
            die "failed to download $source_path from $REPO"
    fi

    chmod "$mode" "$temp"
    mv "$temp" "$destination"
}

resolve_version() {
    if [ -n "$TAILSCALE_VERSION" ]; then
        VERSION=$TAILSCALE_VERSION
        return
    fi

    latest_json="$TMP_DIR/latest.json"
    fetch "$PKGS_BASE/?mode=json&os=linux" "$latest_json" ||
        die "failed to resolve the latest Tailscale $TRACK release"

    VERSION=$(
        tr -d '\n\r' < "$latest_json" |
            sed -n 's/.*"TarballsVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
    )

    [ -n "$VERSION" ] ||
        die "could not parse the latest Tailscale tarball version"
}

download_tailscale() {
    TARBALL="tailscale_${VERSION}_${ARCH}.tgz"
    ARCHIVE="$TMP_DIR/$TARBALL"
    CHECKSUM="$TMP_DIR/$TARBALL.sha256"

    say "Downloading Tailscale $VERSION ($ARCH)..."

    fetch "$PKGS_BASE/$TARBALL" "$ARCHIVE" ||
        die "failed to download $TARBALL"
    fetch "$PKGS_BASE/$TARBALL.sha256" "$CHECKSUM" ||
        die "failed to download checksum for $TARBALL"

    expected=$(sed -n '1{s/[[:space:]].*$//;p;}' "$CHECKSUM")
    actual=$(sha256sum "$ARCHIVE" | sed 's/[[:space:]].*$//')

    [ "${#expected}" -eq 64 ] || die "invalid SHA-256 response for $TARBALL"
    [ "$actual" = "$expected" ] || die "checksum verification failed for $TARBALL"
}

install_binaries() {
    extract_dir="$TMP_DIR/extract"
    mkdir -p "$extract_dir"
    tar -xzf "$ARCHIVE" --strip-components=1 -C "$extract_dir"

    [ -f "$extract_dir/tailscale" ] || die "archive does not contain tailscale"
    [ -f "$extract_dir/tailscaled" ] || die "archive does not contain tailscaled"

    mkdir -p "$DATA_DIR"
    STAGE_DIR=$(mktemp -d "$DATA_DIR/.install.XXXXXXXXXX")

    cp "$extract_dir/tailscale" "$STAGE_DIR/tailscale"
    cp "$extract_dir/tailscaled" "$STAGE_DIR/tailscaled"
    chmod 0755 "$STAGE_DIR/tailscale" "$STAGE_DIR/tailscaled"

    mv "$STAGE_DIR/tailscale" "$DATA_DIR/tailscale"
    mv "$STAGE_DIR/tailscaled" "$DATA_DIR/tailscaled"
    rmdir "$STAGE_DIR"
    STAGE_DIR=""
}

install_setup_files() {
    mkdir -p "$BIN_DIR" "$STATE_DIR" "$CONFIG_DIR" "$UNIT_DIR"
    chmod 0700 "$STATE_DIR"

    project_file bin/tailscale "$BIN_DIR/tailscale" 0755
    ln -sfn ../share/tailscale/tailscaled "$BIN_DIR/tailscaled"

    if [ -e "$DEFAULTS_FILE" ]; then
        say "Preserving existing $DEFAULTS_FILE"
    else
        project_file systemd/tailscaled.defaults "$DEFAULTS_FILE" 0644
    fi

    project_file systemd/tailscaled.service "$UNIT_DIR/tailscaled.service" 0644
    project_file systemd/tailscale-wait-online.service "$UNIT_DIR/tailscale-wait-online.service" 0644
    project_file systemd/tailscale-online.target "$UNIT_DIR/tailscale-online.target" 0644
}

check_path() {
    PATH_READY=0

    resolved=$(command -v tailscale 2>/dev/null || true)
    if [ "$resolved" = "$BIN_DIR/tailscale" ]; then
        PATH_READY=1
        return
    fi

    case ":${PATH:-}:" in
        *:"$BIN_DIR":*) ;;
        *) warn "$BIN_DIR is not on PATH" ;;
    esac

    if [ -n "$resolved" ]; then
        warn "tailscale currently resolves to $resolved instead of $BIN_DIR/tailscale"
    fi
}

check_linger() {
    LINGER_HINT=0

    command -v loginctl >/dev/null 2>&1 || return 0

    linger=$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)
    if [ "$linger" = no ]; then
        LINGER_HINT=1
    fi
}

usage() {
    cat <<'USAGE'
Tailscale User Setup installer

Installs the official Tailscale static binaries as a per-user Linux service.

Environment variables:
  TRACK=stable|unstable
      Tailscale release track. Default: stable.

  TAILSCALE_VERSION=1.102.2
      Install a specific Tailscale version instead of the latest release.
USAGE
}

main() {
    case "${1:-}" in
        -h|--help)
            usage
            exit 0
            ;;
        "") ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac

    need_cmd uname
    need_cmd id
    need_cmd systemctl
    need_cmd mkdir
    need_cmd dirname
    need_cmd mktemp
    need_cmd rm
    need_cmd cp
    need_cmd mv
    need_cmd chmod
    need_cmd ln
    need_cmd sed
    need_cmd tr
    need_cmd tar
    need_cmd sha256sum

    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER=curl
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER=wget
    else
        die "either curl or wget is required"
    fi

    check_environment
    init_paths
    detect_arch
    warn_system_daemon
    find_local_repo

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tailscale-user-setup.XXXXXXXXXX")
    STAGE_DIR=""
    trap cleanup 0
    trap 'exit 1' HUP INT TERM

    resolve_version
    download_tailscale
    install_binaries
    install_setup_files

    systemctl --user daemon-reload
    systemctl --user enable tailscaled.service >/dev/null
    systemctl --user restart tailscaled.service ||
        die "tailscaled.service failed; inspect it with: journalctl --user -u tailscaled.service"

    check_path
    check_linger

    cleanup
    TMP_DIR=""
    trap - 0 HUP INT TERM

    say ""

    if [ "$PATH_READY" = 1 ]; then
        say "Installation complete! Log in to start using Tailscale by running:"
        say ""
        say "tailscale up"
    else
        say "Installation complete!"
        say ""
        say "$BIN_DIR is not on PATH."
        say ""
        say "Add it to PATH, or run:"
        say ""
        say "$BIN_DIR/tailscale up"
    fi

    if [ "$LINGER_HINT" = 1 ]; then
        say ""
        say "To keep the service running after logout, optionally run:"
        say ""
        say '  loginctl enable-linger "$USER"'
    fi
}

# Keep execution at the bottom so a truncated curl | sh download cannot execute
# a partially downloaded installer.
main "$@"
