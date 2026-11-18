#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CTL_PATH="$HOME/.local/bin/wayscriber-ctl.sh"
WAYSCRIBER_BIN="$HOME/.local/bin/wayscriber"
# One build container for every distro. It also builds keyd into dist/keyd/,
# which only Fedora uses (Arch and Debian install keyd from their repos).
WAYSCRIBER_DIST="$SCRIPT_DIR/dist/wayscriber"
KEYD_DIST="$SCRIPT_DIR/dist/keyd"
WAYSCRIBER_CFG_DIR="$HOME/.config/wayscriber"
WAYSCRIBER_CFG="$WAYSCRIBER_CFG_DIR/config.toml"
KEYD_CONF="/etc/keyd/wayscriber.conf"
RECEIPT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wayscriber-numpad"
RECEIPT="$RECEIPT_DIR/receipt"
ACTIVE_FLAG="$RECEIPT_DIR/numpad-active"
CFG_BACKUP_DIR="$RECEIPT_DIR/config-backups"
UNIT_NAME="wayscriber-numpad.service"
UNIT_PATH="$HOME/.config/systemd/user/$UNIT_NAME"
TOGGLE_PATH="$HOME/.local/bin/wayscriber-numpad"
DESKTOP_PATH="$HOME/.local/share/applications/wayscriber-numpad.desktop"
DRY_RUN=false

# Distro is detected at startup so the same script works on Arch, Debian 13+,
# Ubuntu 25.10+ and Fedora hosts (Ubuntu takes the Debian path).
# Distro-specific choices go through these vars.
DISTRO=""
PKG=""
detect_distro() {
    local id="" id_like=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID:-}"
        id_like="${ID_LIKE:-}"
    fi
    case " $id $id_like " in
        *debian*)                       DISTRO="debian"; PKG="apt" ;;
        *arch*)                         DISTRO="arch";   PKG="pacman" ;;
        *fedora*|*rhel*|*centos*|*rocky*|*almalinux*) DISTRO="fedora"; PKG="dnf" ;;
        *)                              DISTRO="unknown"; PKG="" ;;
    esac
}
detect_distro

# Debian renames the keyd binary to keyd.rvaiya (Debian bug #1098982).
# Service, group and config paths are unchanged.
KEYD="keyd"
if [ "$DISTRO" = debian ]; then KEYD="keyd.rvaiya"; fi

# wayscriber opens a native Wayland layer-shell surface. It cannot work in an
# X11 session, even on the same KDE desktop.
is_wayland_session() {
    [ -n "${WAYLAND_DISPLAY:-}" ] && [ "${XDG_SESSION_TYPE:-}" != "x11" ]
}

if [ -t 1 ]; then
    R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' B='\033[1;34m'
    M='\033[1;35m' C='\033[1;36m'
    DIM='\033[2m' BOLD='\033[1m' OFF='\033[0m'
else
    R='' G='' Y='' B='' M='' C='' DIM='' BOLD='' OFF=''
fi

die()  { printf "${R}error:${OFF} %s\n" "$1" >&2; exit 1; }
info() { printf "${B}>>>${OFF} %s\n" "$1"; }
ok()   { printf "  ${G}ok${OFF}  %s\n" "$1"; }
skip() { printf "  ${DIM}--${OFF}  %s\n" "$1"; }
warn() { printf "  ${Y}!!${OFF}  %s\n" "$1"; }

confirm() {
    if $DRY_RUN; then return 0; fi
    printf "  ${Y}?${OFF}   %s [y/N] " "$1"
    read -r ans || return 1
    case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

pick() {
    local i=1
    for opt in "$@"; do
        printf "  ${B}%d${OFF}) %s\n" "$i" "$opt" >&2
        ((i++))
    done
    echo >&2
    printf "Pick [1-%d]: " "$#" >&2
    read -r choice || die "no choice entered"
    echo "$choice"
}

record()   { echo "$1" >> "$RECEIPT"; }
was_done() { [ -f "$RECEIPT" ] && grep -qx "$1" "$RECEIPT" 2>/dev/null; }

banner() {
    printf "\n  ${R}✎${OFF}${Y}✎${OFF}${G}✎${OFF}${C}✎${OFF}${B}✎${OFF}${M}✎${OFF}  "
    printf "${BOLD}wayscriber-numpad${OFF}  "
    printf "${M}✎${OFF}${B}✎${OFF}${C}✎${OFF}${G}✎${OFF}${Y}✎${OFF}${R}✎${OFF}\n"
    printf "  ${DIM}numpad tool-switching for screen annotation, KDE Plasma Wayland${OFF}\n"
}

# 6-hex-digit color -> a colored two-space swatch. No-ops when colors are
# off (piped output, dumb terminal) so scripts consuming this stay clean.
swatch() {
    [ -n "$OFF" ] || return 0
    local hex="$1" r g b
    r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
    printf "\033[48;2;%d;%d;%dm  \033[0m" "$r" "$g" "$b"
}

keyd_cmd() {
    if id -nG | grep -qw keyd; then
        "$KEYD" "$@"
    else
        echo "$KEYD $(printf '%q ' "$@")" | newgrp keyd
    fi
}

is_wayscriber_installed() {
    [ -x "$WAYSCRIBER_BIN" ] || command -v wayscriber &>/dev/null
}

# The binary generated scripts/units should run. install skips copying to
# ~/.local/bin when a wayscriber is already on PATH, so fall back to that.
wayscriber_bin() {
    if [ -x "$WAYSCRIBER_BIN" ]; then echo "$WAYSCRIBER_BIN"; else command -v wayscriber || echo "$WAYSCRIBER_BIN"; fi
}

is_daemon_running() {
    # A crashed/finished daemon can linger as a zombie until its parent
    # reaps it. pgrep matches those too, which makes `status` claim the
    # daemon is running and makes `enable` refuse to start. Only treat a
    # non-zombie wayscriber process as alive.
    local pid state
    while read -r pid state; do
        [ -n "$pid" ] || continue
        case "$state" in Z*) continue ;; esac
        return 0
    done < <(ps -u "$(id -u)" -o pid=,stat=,comm= | awk '$3 == "wayscriber" { print $1, $2 }')
    return 1
}

stop_numpad() {
    keyd_cmd bind reset 2>/dev/null || true
    pkill -u "$(id -u)" -x wayscriber 2>/dev/null || true
    rm -f "$ACTIVE_FLAG"
}

is_numpad_active() {
    [ -f "$ACTIVE_FLAG" ]
}

is_config_current() {
    cmp -s "$SCRIPT_DIR/config.toml" "$WAYSCRIBER_CFG"
}

is_unit_active() {
    systemctl --user is-active --quiet "$UNIT_NAME" 2>/dev/null
}

is_app_installed() {
    [ -x "$TOGGLE_PATH" ] && [ -f "$UNIT_PATH" ] && [ -f "$DESKTOP_PATH" ]
}

# ── Help ──────────────────────────────────────────────

cmd_help() {
    banner
    cat <<EOF

Usage: ./wayscriber.sh [command]        (no command: menu)

  start   | on  | enable      Turn Drawing Mode on
  stop    | off | disable     Turn Drawing Mode off
  status                      What's installed and running
  install | setup             Set everything up (--dry-run to preview)
  update  | upgrade           Rebuild wayscriber from upstream
  uninstall | remove          Remove the numpad wiring
  help                        This screen

Everyday: click 'Drawing Mode' in the app menu to turn it on or off.

Numpad, while Drawing Mode is on (keep Num Lock on):
  KP1 show/hide drawing   KP2 undo   KP3 redo   KP7 clear   KP8 passthrough
  KP9 $(swatch FF0000)red   KP0 $(swatch 0000FF)blue   KP4 $(swatch 222222)dark   KP5 $(swatch FFFF00)highlighter   KP6 $(swatch 999999)eraser

Details and troubleshooting: README.md
EOF
}

# ── Status ────────────────────────────────────────────

cmd_status() {
    banner
    echo
    info "Environment"
    if [ "$DISTRO" != unknown ]; then ok "detected distro: ${PRETTY_NAME:-$DISTRO} (packages via $PKG)"; else warn "unsupported distro - Arch, Debian 13+, Ubuntu 25.10+ and Fedora only"; fi
    if is_wayland_session; then ok "Wayland session (WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset})"; else warn "X11 or no Wayland session (XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unknown}) - wayscriber cannot draw here"; fi

    echo
    info "Installation"

    if command -v "$KEYD" &>/dev/null; then ok "keyd installed"; else warn "keyd not installed"; fi
    if id -nG "$USER" | grep -qw keyd; then ok "$USER in keyd group"; else warn "$USER not in keyd group (log out/in after install)"; fi
    if systemctl is-active keyd.service &>/dev/null; then ok "keyd service running"; else warn "keyd service not running"; fi
    if [ -f "$KEYD_CONF" ]; then ok "keyd config present"; else warn "keyd config missing ($KEYD_CONF)"; fi
    if [ -x "$CTL_PATH" ]; then ok "bridge script present ($CTL_PATH)"; else warn "bridge script missing ($CTL_PATH)"; fi
    if is_wayscriber_installed; then ok "wayscriber binary present"; else warn "wayscriber not built/installed yet"; fi
    if [ ! -f "$WAYSCRIBER_CFG" ]; then
        warn "wayscriber config missing"
    elif is_config_current; then
        ok "wayscriber config matches this repo"
    else
        warn "wayscriber config differs from this repo's config.toml (run install to update it)"
    fi
    if is_app_installed; then ok "'Drawing Mode' app installed ($UNIT_NAME)"; else warn "'Drawing Mode' app missing (run install)"; fi
    if is_daemon_running; then ok "wayscriber running"; else skip "wayscriber not running (starts with Drawing Mode)"; fi

    echo
    info "Numpad"
    if is_unit_active; then ok "Drawing Mode is on"; else skip "Drawing Mode is off"; fi
    if is_numpad_active; then
        ok "drawing controls active (numpad remapped)"
        printf "      KP9 $(swatch FF0000)red  KP0 $(swatch 0000FF)blue  KP4 $(swatch 222222)dark  KP5 $(swatch FFFF00)highlighter  KP6 $(swatch 999999)eraser\n"
    else
        skip "numpad is typing normal numbers"
    fi
    echo
}

# ── Bridge script generator ──────────────────────────

generate_ctl() {
    local passwd_entry target_home target_gid
    passwd_entry="$(getent passwd "$USER")"
    target_home="$(printf '%s' "$passwd_entry" | cut -d: -f6)"
    target_gid="$(printf '%s' "$passwd_entry" | cut -d: -f4)"
    [ -n "$target_home" ] || die "could not determine home directory for $USER"
    [ -n "$target_gid" ] || die "could not determine primary group for $USER"
    cat <<CTLEOF
#!/bin/bash
# Generated by wayscriber.sh install. Do not edit manually.
# keyd (root) calls this to forward wayscriber control commands
# into the target user's session.
set -euo pipefail
TARGET_USER=$USER
TARGET_UID=\$(id -u "\$TARGET_USER")
RUNTIME="/run/user/\$TARGET_UID"

# keyd runs this as root: drop to the session user and discard root's
# supplementary groups. setpriv --clear-groups needs CAP_SETGID, so when the
# user runs this directly (for testing) just set the session environment.
if [ "\$(id -u)" -eq 0 ]; then
    exec setpriv --reuid="\$TARGET_USER" --regid="$target_gid" --clear-groups \\
        env HOME="$target_home" XDG_RUNTIME_DIR="\$RUNTIME" \\
        DBUS_SESSION_BUS_ADDRESS="unix:path=\$RUNTIME/bus" \\
        "$(wayscriber_bin)" "\$@"
fi
exec env HOME="$target_home" XDG_RUNTIME_DIR="\$RUNTIME" \\
    DBUS_SESSION_BUS_ADDRESS="unix:path=\$RUNTIME/bus" \\
    "$(wayscriber_bin)" "\$@"
CTLEOF
}

# ── Drawing Mode app generators ──────────────────────
# Drawing Mode = the systemd user unit below, started/stopped by the toggle
# script, which the app-menu launcher runs. No terminal, no autostart: the
# unit has no [Install] section, so it only runs when turned on.

generate_unit() {
    cat <<UNITEOF
# Generated by wayscriber.sh install. Do not edit manually.
# Not enabled on purpose: started/stopped on demand by $TOGGLE_PATH.
[Unit]
Description=Drawing Mode (wayscriber with numpad controls)
Documentation=https://github.com/devmobasa/wayscriber
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStartPre=/bin/sh -c '[ -n "\$\$WAYLAND_DISPLAY" ] && [ -S "\$\$XDG_RUNTIME_DIR/\$\$WAYLAND_DISPLAY" ]'
ExecStart="$(wayscriber_bin)" --daemon
ExecStartPost="$TOGGLE_PATH" keys-on
ExecStopPost=-"$TOGGLE_PATH" keys-off
# SIGTERM only the daemon so it can close its own overlay child; killing
# both at once makes its shutdown fail with exit 1.
KillMode=mixed
# A hung start/stop must not leave the menu click waiting the 90s default.
TimeoutStartSec=20
TimeoutStopSec=5
UNITEOF
}

generate_toggle() {
    cat <<TOGEOF
#!/bin/bash
# Generated by wayscriber.sh install (only if missing, so edits here stay).
# Drawing Mode on/off switch. No argument = toggle.
set -uo pipefail
# Desktop popups on turn on/off and on failure ("Press 1 on the number
# pad..."). On by default; set to false to silence them. Failures are
# always printed and in the journal.
POPUPS=true
UNIT="$UNIT_NAME"
KEYD="$KEYD"
CTL="$CTL_PATH"
FLAG="$ACTIVE_FLAG"
TOGEOF
    cat <<'TOGEOF'

notify() {
    [ "$POPUPS" = true ] || return 0
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send --app-name="Drawing Mode" --icon=draw-freehand \
        --urgency="${3:-normal}" "$1" "$2" 2>/dev/null || true
}

keyd_run() {
    if id -nG | grep -qw keyd; then
        "$KEYD" "$@"
    else
        echo "$KEYD $(printf '%q ' "$@")" | newgrp keyd
    fi
}

is_on() { systemctl --user is-active --quiet "$UNIT"; }

# One switch action at a time. A double-click launches this twice; without
# the lock the second launch turns Drawing Mode straight back off. Not used
# by keys-on/keys-off, which run inside the first launch's start/stop.
lock_or_exit() {
    exec 9>"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wayscriber-numpad.lock" || return 0
    flock -n 9 || exit 0
}

# Best-guess reason for a failed start, in plain words for the popup.
why_failed() {
    # Same Wayland test as the unit's ExecStartPre, on the unit's environment.
    local env wd rt
    env="$(systemctl --user show-environment 2>/dev/null)"
    wd="$(printf '%s\n' "$env" | sed -n 's/^WAYLAND_DISPLAY=//p')"
    rt="$(printf '%s\n' "$env" | sed -n 's/^XDG_RUNTIME_DIR=//p')"
    if pgrep -u "$(id -u)" -x wayscriber >/dev/null 2>&1; then
        echo "Another copy of wayscriber is already running. Close it, or restart the computer, then try again."
    elif ! systemctl is-active --quiet keyd.service; then
        echo "The keyboard helper (keyd) isn't running. Restarting the computer usually fixes this."
    elif [ -z "$wd" ] || [ ! -S "$rt/$wd" ]; then
        echo "This only works in a Plasma (Wayland) session. Log out and pick Plasma (Wayland) at the login screen."
    else
        echo "Nothing was changed. Try again, or log out and back in first."
    fi
}

turn_on() {
    if is_on; then
        notify "Drawing Mode is already on" \
            "Press 1 on the number pad to start or stop drawing."
        return 0
    fi
    if systemctl --user start "$UNIT" && sleep 0.5 && is_on; then
        notify "Drawing Mode is on" \
            "Press 1 on the number pad to start drawing. Press 1 again when you're done."
        return 0
    fi
    local why
    why="$(why_failed)"
    echo "Drawing Mode didn't start: $why" >&2
    notify "Drawing Mode didn't start" "$why" critical
    return 1
}

turn_off() {
    if ! is_on; then
        notify "Drawing Mode is already off" "Your number pad types numbers."
        return 0
    fi
    if ! systemctl --user stop "$UNIT"; then
        notify "Drawing Mode couldn't turn off" \
            "Restarting the computer will turn it off." critical
        return 1
    fi
    notify "Drawing Mode is off" "Your number pad types numbers again."
}

case "${1:-toggle}" in
    toggle)   lock_or_exit; if is_on; then turn_off; else turn_on; fi ;;
    on)       lock_or_exit; turn_on ;;
    off)      lock_or_exit; turn_off ;;
    status)   if is_on; then echo "Drawing Mode is on"; else echo "Drawing Mode is off"; fi ;;
    # Called by the systemd unit only (ExecStartPost / ExecStopPost).
    keys-on)
        keyd_run bind "kp1=command($CTL --daemon-toggle)" \
            "kp8=command($CTL --light-toggle)" || exit 1
        mkdir -p "$(dirname "$FLAG")" && touch "$FLAG"
        ;;
    keys-off)
        keyd_run bind reset >/dev/null 2>&1 || true
        rm -f "$FLAG"
        ;;
    *)  echo "usage: $(basename "$0") [toggle|on|off|status]" >&2; exit 2 ;;
esac
TOGEOF
}

generate_desktop() {
    cat <<DESKEOF
[Desktop Entry]
Type=Application
Name=Drawing Mode
GenericName=Draw on Screen
Comment=Turn number-pad drawing on or off
Icon=draw-freehand
Exec="$TOGGLE_PATH"
Terminal=false
Categories=Utility;
Keywords=draw;annotate;pen;highlighter;numpad;wayscriber;
Actions=on;off;

[Desktop Action on]
Name=Turn On
Exec="$TOGGLE_PATH" on

[Desktop Action off]
Name=Turn Off
Exec="$TOGGLE_PATH" off
DESKEOF
}

# ── Install ───────────────────────────────────────────

cmd_install() {
    case "${1:-}" in
        ""|--dry-run) ;;
        *) die "unknown install option: $1 (expected: --dry-run)" ;;
    esac
    if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=true; fi

    banner
    echo

    [ "$(id -u)" -eq 0 ] && die "run as your normal user, not root (sudo is used where needed)"
    [ "$DISTRO" != unknown ] || die "unsupported distro (only Arch-based, Debian 13+, Ubuntu 25.10+ and Fedora are supported)"
    command -v docker &>/dev/null || die "docker not found (build happens in a container, install docker first)"
    docker compose version &>/dev/null || die "docker compose not found (install docker-compose-plugin or docker-compose)"
    command -v sudo &>/dev/null || die "sudo not found (install sudo first: apt install sudo / dnf install sudo / pacman -S sudo)"
    command -v systemctl &>/dev/null || die "systemd not found (keyd and Drawing Mode both run as systemd services)"
    systemctl --user show-environment &>/dev/null || die "cannot reach your systemd user manager (systemctl --user). Run install from a terminal inside your desktop session, not via su/sudo/ssh"
    [ -f "$SCRIPT_DIR/keyd-wayscriber.conf" ] || die "keyd-wayscriber.conf not found in $SCRIPT_DIR"
    [ -f "$SCRIPT_DIR/config.toml" ] || die "config.toml not found in $SCRIPT_DIR"

    # Do not require make here on Fedora: a fresh system may not have it,
    # and it is installed just before keyd's Makefile is invoked.
    case "$DISTRO" in
        debian) command -v apt-get &>/dev/null || die "apt-get not found (Debian or Ubuntu expected)" ;;
        fedora) command -v dnf &>/dev/null || die "dnf not found (Fedora expected)" ;;
        *)      command -v pacman &>/dev/null || die "pacman not found (Arch-based distro expected)" ;;
    esac
    # The binary is built on Debian 13 (glibc 2.41) and links the host's
    # glibc, so an older host cannot run it.
    local glibc
    glibc="$(getconf GNU_LIBC_VERSION | awk '{print $2}')"
    [ "$(printf '%s\n' 2.41 "$glibc" | sort -V | head -1)" = 2.41 ] \
        || die "glibc $glibc is too old (2.41+ needed: Debian 13+, Ubuntu 25.10+, current Arch or Fedora)"
    [ -f "$SCRIPT_DIR/Dockerfile" ] || die "Dockerfile not found in $SCRIPT_DIR"
    [ -f "$SCRIPT_DIR/docker-compose.yml" ] || die "docker-compose.yml not found in $SCRIPT_DIR"

    local need_keyd=false need_wayscriber=false need_build=false
    command -v "$KEYD" &>/dev/null || need_keyd=true
    is_wayscriber_installed || need_wayscriber=true
    if $need_keyd || $need_wayscriber; then need_build=true; fi

    local plan=()
    local need_sudo=false
    local need_logout=false

    if $need_keyd; then
        if [ "$DISTRO" = fedora ]; then
            plan+=("Build keyd v2.6.0 from pinned source in the container, then install with make (sudo)")
            command -v make &>/dev/null || plan+=("Install make first (needed by keyd's Makefile)")
        else
            plan+=("Install keyd via $PKG (sudo)")
        fi
        need_sudo=true
    fi
    if ! getent group keyd &>/dev/null; then
        plan+=("Create keyd group (sudo)"); need_sudo=true
    fi
    if ! id -nG "$USER" | grep -qw keyd; then
        plan+=("Add $USER to keyd group (sudo)"); need_sudo=true; need_logout=true
    fi
    if [ ! -f "$KEYD_CONF" ]; then plan+=("Write keyd config to /etc/keyd/wayscriber.conf (sudo)"); need_sudo=true; fi
    if ! systemctl is-enabled keyd.service &>/dev/null 2>&1; then plan+=("Enable keyd.service (sudo)"); need_sudo=true; fi
    # A previous install may have been interrupted after the binary was
    # copied but before the deps were recorded. Key this off the receipt,
    # not off need_wayscriber, so such a partial install gets repaired.
    if ! was_done "installed_wayscriber_deps"; then
        if [ "$DISTRO" = debian ]; then
            plan+=("Install wayscriber runtime deps via apt: libcairo2 libpango-1.0-0 libwayland-client0 libxkbcommon0 libgtk-4-1 libgtk4-layer-shell0 libadwaita-1-0 wl-clipboard grim slurp (sudo)")
        elif [ "$DISTRO" = fedora ]; then
            plan+=("Install wayscriber runtime deps via dnf: cairo pango libwayland-client libxkbcommon gtk4 gtk4-layer-shell libadwaita make (plus wl-clipboard grim slurp when available) (sudo)")
        else
            plan+=("Install wayscriber runtime deps via pacman: cairo wayland pango libxkbcommon gtk4 gtk4-layer-shell libadwaita wl-clipboard grim slurp (sudo)")
        fi
        need_sudo=true
    fi
    if $need_build; then
        plan+=("Build wayscriber (and keyd on Fedora) in a disposable Docker container (nothing touches the host)")
    fi
    if $need_wayscriber; then
        plan+=("Install binary to $WAYSCRIBER_BIN (no sudo). No service, no autostart")
    fi
    if [ ! -f "$WAYSCRIBER_CFG" ]; then
        plan+=("Install numpad tool presets to $WAYSCRIBER_CFG")
    elif ! is_config_current; then
        plan+=("Replace $WAYSCRIBER_CFG with this repo's config.toml (old copy saved to $CFG_BACKUP_DIR)")
    fi
    if [ ! -x "$CTL_PATH" ]; then plan+=("Generate bridge script at $CTL_PATH"); fi
    if ! is_app_installed; then
        plan+=("Add 'Drawing Mode' to the app menu (on-demand systemd user unit, not autostarted)")
    fi

    if [ ${#plan[@]} -eq 0 ]; then
        ok "everything already installed."
        info "Open 'Drawing Mode' from the app menu, or run: ./wayscriber.sh start"
        DRY_RUN=false
        return 0
    fi

    info "This will:"
    for step in "${plan[@]}"; do printf "      - %s\n" "$step"; done
    if $need_sudo; then
        printf "\n      ${DIM}Steps marked (sudo) will ask for your password once.${OFF}\n"
    fi
    echo

    if $DRY_RUN; then
        printf "${Y}Dry-run complete. No changes were made.${OFF}\n"
        echo
        DRY_RUN=false
        return 0
    fi

    if ! confirm "Proceed?"; then
        echo "Aborted."
        DRY_RUN=false
        return 1
    fi
    echo

    mkdir -p "$RECEIPT_DIR"

    if $need_build; then
        info "Building in a disposable Docker container..."
        # Create the bind-mount target as this user first; Docker otherwise
        # creates it root-owned and later cleanup becomes awkward.
        mkdir -p "$SCRIPT_DIR/dist"
        (cd "$SCRIPT_DIR" && docker compose build builder && docker compose run --rm builder)
        [ -x "$WAYSCRIBER_DIST" ] || die "docker build did not produce $WAYSCRIBER_DIST"
        if [ "$DISTRO" = fedora ]; then
            [ -f "$KEYD_DIST/Makefile" ] || die "docker build did not produce the keyd tree in $KEYD_DIST"
            [ -f "$KEYD_DIST/README.md" ] || die "docker build did not produce the keyd README in $KEYD_DIST"
        fi
        ok "build finished (container discarded, only the artifacts were kept)"
    fi

    if $need_keyd; then
        info "Installing keyd..."
        if [ "$DISTRO" = fedora ]; then
            # Fresh Fedora systems may have no make. keyd's Makefile needs
            # it, and the runtime-deps step below runs later, so install it
            # here first if necessary.
            if ! command -v make &>/dev/null; then
                sudo dnf install -y make
                ok "make installed"
            fi
            # keyd's Makefile writes keyd.service into its source dir while
            # installing. Use a user-owned copy so root-owned build artifacts
            # in dist/keyd never need to be modified.
            (
                tmp="$(mktemp -d)"
                trap 'rm -rf "$tmp"' EXIT
                cp -R "$KEYD_DIST" "$tmp/keyd"
                sudo make -C "$tmp/keyd" install PREFIX=/usr
                if [ "$DISTRO" = fedora ] && command -v restorecon &>/dev/null; then
                    sudo restorecon -RF /usr/bin/keyd /usr/bin/keyd-application-mapper \
                        /usr/lib/systemd/system/keyd.service /usr/lib/sysusers.d/keyd.conf \
                        /usr/share/keyd /usr/share/doc/keyd
                fi
                sudo systemctl daemon-reload
            )
        elif [ "$DISTRO" = debian ]; then
            sudo apt-get update
            sudo apt-get install -y keyd
        else
            sudo pacman -S --needed --noconfirm keyd
        fi
        record "installed_keyd"
        ok "keyd installed"
    fi

    if ! getent group keyd &>/dev/null; then
        sudo groupadd keyd
        record "created_keyd_group"
        ok "keyd group created"
    fi

    if ! id -nG "$USER" | grep -qw keyd; then
        sudo usermod -aG keyd "$USER"
        record "added_keyd_group"
        ok "$USER added to keyd group"
    fi

    if [ ! -f "$KEYD_CONF" ]; then
        sudo install -Dm644 "$SCRIPT_DIR/keyd-wayscriber.conf" "$KEYD_CONF"
        if [ "$DISTRO" = fedora ] && command -v restorecon &>/dev/null; then
            sudo restorecon -F "$KEYD_CONF"
        fi
        # Debian's keyd package starts the daemon on install, before this
        # config exists. keyd only reads configs at startup; without this
        # it runs with none loaded and every `keyd bind` fails.
        sudo systemctl try-restart keyd.service
        record "installed_keyd_config"
        ok "keyd config installed"
    fi

    if ! systemctl is-enabled keyd.service &>/dev/null 2>&1; then
        sudo systemctl enable --now keyd.service
        record "enabled_keyd_service"
        ok "keyd service enabled"
    elif ! systemctl is-active keyd.service &>/dev/null 2>&1; then
        sudo systemctl start keyd.service
        ok "keyd service started"
    fi

    if ! was_done "installed_wayscriber_deps"; then
        info "Installing wayscriber's runtime dependencies..."
        if [ "$DISTRO" = debian ]; then
            sudo apt-get update
            sudo apt-get install -y --no-install-recommends \
                libcairo2 libpango-1.0-0 libwayland-client0 libxkbcommon0 \
                libgtk-4-1 libgtk4-layer-shell0 libadwaita-1-0 \
                wl-clipboard grim slurp
        elif [ "$DISTRO" = fedora ]; then
            # Fedora/RHEL has no package literally named `wayland` (only
            # wayland-devel/wayland-utils); the runtime client library is
            # libwayland-client. Installing already-present packages is fine.
            sudo dnf install -y \
                cairo pango libwayland-client libxkbcommon \
                gtk4 gtk4-layer-shell libadwaita make
            # Screenshot helpers are optional and are missing from some
            # RHEL-family base repos (they live in EPEL there).
            if ! sudo dnf install -y wl-clipboard grim slurp; then
                warn "wl-clipboard/grim/slurp unavailable from enabled repos; screenshot features need them (EPEL on RHEL-family)"
            fi
        else
            sudo pacman -S --needed --noconfirm \
                cairo wayland pango libxkbcommon \
                gtk4 gtk4-layer-shell libadwaita wl-clipboard grim slurp
        fi
        record "installed_wayscriber_deps"
        ok "runtime dependencies installed"
    fi

    if $need_wayscriber; then
        mkdir -p "$HOME/.local/bin"
        install -Dm755 "$WAYSCRIBER_DIST" "$WAYSCRIBER_BIN"
        record "installed_wayscriber"
        ok "wayscriber installed to $WAYSCRIBER_BIN"
    fi

    local cfg_replaced=false
    if [ ! -f "$WAYSCRIBER_CFG" ]; then
        mkdir -p "$WAYSCRIBER_CFG_DIR"
        install -Dm644 "$SCRIPT_DIR/config.toml" "$WAYSCRIBER_CFG"
        record "installed_wayscriber_config"
        ok "numpad tool presets installed to $WAYSCRIBER_CFG"
    elif ! is_config_current; then
        # This repo's config.toml is the source of truth. Keep the old copy.
        local saved
        saved="$CFG_BACKUP_DIR/config.toml.$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$CFG_BACKUP_DIR"
        cp -a "$WAYSCRIBER_CFG" "$saved"
        install -m644 "$SCRIPT_DIR/config.toml" "$WAYSCRIBER_CFG"
        cfg_replaced=true
        ok "wayscriber config updated to this repo's version (old copy: $saved)"
    else
        skip "wayscriber config already matches this repo"
    fi

    if [ ! -x "$CTL_PATH" ]; then
        mkdir -p "$HOME/.local/bin"
        generate_ctl > "$CTL_PATH"
        chmod 755 "$CTL_PATH"
        record "installed_bridge_script"
        ok "bridge script generated"
    fi

    if ! is_app_installed; then
        mkdir -p "$HOME/.local/bin" "$(dirname "$UNIT_PATH")" "$(dirname "$DESKTOP_PATH")"
        generate_toggle > "$TOGGLE_PATH"
        chmod 755 "$TOGGLE_PATH"
        generate_unit > "$UNIT_PATH"
        generate_desktop > "$DESKTOP_PATH"
        # Record before anything else can fail, so uninstall still finds them.
        record "installed_drawing_mode"
        systemctl --user daemon-reload
        ok "'Drawing Mode' added to the app menu"
    fi

    # wayscriber reads its config at start, so a running one keeps the old one.
    if $cfg_replaced && is_unit_active; then
        systemctl --user restart "$UNIT_NAME"
        ok "Drawing Mode restarted to load the new config"
    fi

    echo
    printf "${G}${BOLD}Setup complete.${OFF}\n"
    if $need_logout; then
        info "Run 'newgrp keyd' to activate the group in this terminal."
        printf "      ${DIM}(or log out and back in)${OFF}\n"
    fi
    if ! is_wayland_session; then
        warn "Not in a Wayland session right now. Log out and select 'Plasma (Wayland)' before running 'start'."
    fi
    info "Then open 'Drawing Mode' from the app menu (click it again to turn it off)."
    printf "      ${DIM}Same thing from a terminal: ./wayscriber.sh start / stop${OFF}\n"
    echo

    DRY_RUN=false
}

# ── Update ────────────────────────────────────────────

cmd_update() {
    is_wayscriber_installed || die "wayscriber not installed. Run: ./wayscriber.sh install"
    command -v docker &>/dev/null || die "docker not found"

    [ -f "$SCRIPT_DIR/docker-compose.yml" ] || die "docker-compose.yml not found in $SCRIPT_DIR"

    banner
    echo
    info "This rebuilds wayscriber from the latest upstream ${WAYSCRIBER_REF:-main}"
    info "branch (--no-cache, so it actually refetches) and reinstalls the"
    info "binary. Same disposable-container build as install, nothing"
    info "touches the host. Takes effect the next time Drawing Mode starts."
    echo
    if ! confirm "Proceed?"; then
        echo "Aborted."
        return 1
    fi
    echo

    mkdir -p "$SCRIPT_DIR/dist"
    (cd "$SCRIPT_DIR" && docker compose build --no-cache builder && docker compose run --rm builder)
    [ -x "$WAYSCRIBER_DIST" ] || die "docker build did not produce $WAYSCRIBER_DIST"
    ok "rebuilt (container discarded, only the artifacts were kept)"

    install -Dm755 "$WAYSCRIBER_DIST" "$WAYSCRIBER_BIN"
    ok "wayscriber reinstalled to $WAYSCRIBER_BIN"
    echo
}

# ── Enable / disable numpad ──────────────────────────

cmd_enable() {
    if ! is_wayland_session; then
        die "wayscriber needs a Wayland session (current: ${XDG_SESSION_TYPE:-unknown}, WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}).
      Log out and pick 'Plasma (Wayland)' at the login screen; KDE on X11
      cannot host wayscriber's layer-shell overlay."
    fi
    command -v "$KEYD" &>/dev/null || die "keyd not found. Run: ./wayscriber.sh install"
    [ -x "$CTL_PATH" ] || die "bridge script missing. Run: ./wayscriber.sh install"
    is_wayscriber_installed || die "wayscriber not installed. Run: ./wayscriber.sh install"
    if ! id -nG | grep -qw keyd; then
        getent group keyd | grep -qw "$USER" || die "$USER not in keyd group. Run: ./wayscriber.sh install"
    fi
    if ! systemctl is-active keyd.service &>/dev/null; then
        if systemctl is-enabled keyd.service &>/dev/null; then
            warn "keyd service is dead (crash?). Restarting..."
            sudo systemctl restart keyd.service
            sleep 0.5
            systemctl is-active keyd.service &>/dev/null || die "keyd failed to restart. Check: journalctl -u keyd"
            ok "keyd restarted"
        else
            die "keyd service not enabled. Run: ./wayscriber.sh install"
        fi
    fi
    is_app_installed || die "Drawing Mode not installed. Run: ./wayscriber.sh install"
    if is_unit_active; then
        ok "Drawing Mode is already on."
        return 0
    fi
    if is_daemon_running; then
        warn "wayscriber is already running outside Drawing Mode."
        echo "      Stop it first: ./wayscriber.sh stop"
        return 1
    fi
    # Flag left behind with nothing running (power loss, reboot, keyd
    # restart): stale, clear it instead of refusing to start.
    if is_numpad_active; then stop_numpad >/dev/null; fi

    if ! "$TOGGLE_PATH" on || ! is_unit_active; then
        die "Drawing Mode didn't start. See why: journalctl --user -u $UNIT_NAME -n 30"
    fi
    ok "Drawing Mode is on (runs in the background, this terminal can close)."
    echo "      KP1 to show/hide the overlay. Once shown, KP2-KP0 switch tools"
    echo "      (handled by wayscriber itself, not keyd). See ./wayscriber.sh help."
    echo "      Turn off: 'Drawing Mode' in the app menu, or ./wayscriber.sh stop"
}

cmd_disable() {
    # systemctl directly: works even if the toggle script was deleted.
    systemctl --user stop "$UNIT_NAME" 2>/dev/null || true
    # Leftovers from a killed run.
    stop_numpad
    ok "Drawing Mode is off: numpad types numbers, wayscriber stopped."
}

# ── Uninstall ─────────────────────────────────────────

cmd_uninstall() {
    banner
    echo
    if ! confirm "Remove keyd + numpad wiring for $USER? (wayscriber itself is left alone)"; then
        echo "Aborted."
        return 1
    fi
    echo

    if is_unit_active || is_numpad_active || is_daemon_running; then cmd_disable; echo; fi

    info "Uninstalling numpad wiring for $USER"
    echo

    if was_done "installed_drawing_mode"; then
        rm -f "$TOGGLE_PATH" "$UNIT_PATH" "$DESKTOP_PATH"
        systemctl --user daemon-reload 2>/dev/null || true
        ok "removed 'Drawing Mode' app (launcher, toggle script, systemd user unit)"
    else
        skip "'Drawing Mode' app (not installed by us)"
    fi

    if was_done "installed_bridge_script"; then
        if [ -f "$CTL_PATH" ]; then rm "$CTL_PATH"; ok "removed $CTL_PATH"; else skip "bridge script (already gone)"; fi
    else
        skip "bridge script (not installed by us)"
    fi

    if was_done "installed_keyd_config"; then
        if [ -f "$KEYD_CONF" ]; then
            if sudo rm "$KEYD_CONF" 2>/dev/null; then
                sudo "$KEYD" reload 2>/dev/null || true
                ok "removed $KEYD_CONF"
            else
                warn "could not remove $KEYD_CONF (sudo failed)"
            fi
        else
            skip "keyd config (already gone)"
        fi
    else
        skip "keyd config (not installed by us)"
    fi

    if was_done "enabled_keyd_service"; then
        if systemctl is-enabled keyd.service &>/dev/null 2>&1; then
            sudo systemctl disable --now keyd.service 2>/dev/null && ok "keyd service disabled" \
                || warn "could not disable keyd service (sudo failed)"
        fi
    else
        skip "keyd service (not installed by us)"
    fi

    if was_done "added_keyd_group"; then
        if id -nG "$USER" | grep -qw keyd; then
            sudo gpasswd -d "$USER" keyd 2>/dev/null && ok "removed $USER from keyd group" \
                || warn "could not remove $USER from keyd group (sudo failed)"
        fi
    else
        skip "keyd group (not added by us)"
    fi

    # On Fedora keyd came from a source build, not a package: remove
    # exactly the files `make install PREFIX=/usr` created. The (empty) keyd
    # group is deliberately left alone - removing it could affect anything
    # else that happens to use it.
    if [ "$DISTRO" = fedora ] && was_done "installed_keyd"; then
        info "Removing source-built keyd files..."
        sudo rm -f /usr/bin/keyd /usr/bin/keyd-application-mapper \
            /usr/lib/systemd/system/keyd.service /usr/lib/sysusers.d/keyd.conf \
            /usr/share/man/man1/keyd.1.gz \
            /usr/share/man/man1/keyd-application-mapper.1.gz
        sudo rm -rf /usr/share/keyd /usr/share/doc/keyd
        sudo systemctl daemon-reload
        ok "source-built keyd files removed (keyd group kept)"
    fi

    echo
    if was_done "installed_keyd" && [ "$DISTRO" != fedora ]; then
        warn "keyd package was installed by this script but NOT removed."
        if [ "$DISTRO" = debian ]; then
            printf "      Remove manually: ${DIM}sudo apt-get remove keyd${OFF}\n"
        else
            printf "      Remove manually: ${DIM}sudo pacman -R keyd${OFF}\n"
        fi
    fi
    if was_done "installed_wayscriber"; then
        warn "wayscriber itself was NOT removed (it's not part of the numpad wiring)."
        printf "      Remove manually:\n"
        printf "        ${DIM}rm -f %s${OFF}\n" "$WAYSCRIBER_BIN"
        printf "        ${DIM}rm -rf %s/dist${OFF}\n" "$SCRIPT_DIR"
        printf "        ${DIM}docker compose -f %s/docker-compose.yml down --rmi local${OFF}\n" "$SCRIPT_DIR"
    fi
    if was_done "installed_wayscriber_deps"; then
        warn "wayscriber's runtime packages were NOT removed (other apps may use them)."
        if [ "$DISTRO" = debian ]; then
            printf "      Remove manually: ${DIM}sudo apt-get remove libcairo2 libpango-1.0-0 libwayland-client0 libxkbcommon0 libgtk-4-1 libgtk4-layer-shell0 libadwaita-1-0 wl-clipboard grim slurp${OFF}\n"
        elif [ "$DISTRO" = fedora ]; then
            printf "      Remove manually: ${DIM}sudo dnf remove cairo pango libwayland-client libxkbcommon gtk4 gtk4-layer-shell libadwaita wl-clipboard grim slurp make${OFF}\n"
        else
            printf "      Remove manually: ${DIM}sudo pacman -R cairo wayland pango libxkbcommon gtk4 gtk4-layer-shell libadwaita wl-clipboard grim slurp${OFF}\n"
        fi
    fi

    rm -f "$RECEIPT"
    rmdir "$RECEIPT_DIR" 2>/dev/null || true

    echo
    ok "uninstall complete."
}

# ── Menus ─────────────────────────────────────────────

menu_not_installed() {
    banner
    warn "Not fully installed."
    echo
    local choice
    choice=$(pick "Install" "Preview install (no changes)" "Status" "Help")
    echo
    case "$choice" in
        1) cmd_install ;;
        2) cmd_install --dry-run ;;
        3) cmd_status ;;
        4) cmd_help ;;
        *) die "invalid choice" ;;
    esac
}

menu_ready() {
    banner
    printf "  ${G}${BOLD}ready to draw${OFF}\n"
    echo
    local choice
    if is_unit_active || is_numpad_active; then
        choice=$(pick "Turn Drawing Mode off" "Status" "Update wayscriber" "Uninstall")
        echo
        case "$choice" in
            1) cmd_disable ;;
            2) cmd_status ;;
            3) cmd_update ;;
            4) cmd_uninstall ;;
            *) die "invalid choice" ;;
        esac
    else
        choice=$(pick "Turn Drawing Mode on" "Status" "Update wayscriber" "Uninstall")
        echo
        case "$choice" in
            1) cmd_enable ;;
            2) cmd_status ;;
            3) cmd_update ;;
            4) cmd_uninstall ;;
            *) die "invalid choice" ;;
        esac
    fi
}

# ── Main ──────────────────────────────────────────────

main() {
    case "${1:-}" in
        install|setup)          shift; cmd_install "$@" ;;
        enable|start|on)        cmd_enable ;;
        disable|stop|off)       cmd_disable ;;
        update|upgrade)         cmd_update ;;
        status)                 cmd_status ;;
        uninstall|remove)       cmd_uninstall ;;
        help|-h|--help)         cmd_help ;;
        "")
            if ! command -v "$KEYD" &>/dev/null || [ ! -f "$KEYD_CONF" ] || ! is_wayscriber_installed || [ ! -x "$CTL_PATH" ] || ! is_app_installed; then
                menu_not_installed
            else
                menu_ready
            fi
            ;;
        *)  die "unknown command: $1
      try: start, stop, status, install, update, uninstall, help" ;;
    esac
}

main "$@"
