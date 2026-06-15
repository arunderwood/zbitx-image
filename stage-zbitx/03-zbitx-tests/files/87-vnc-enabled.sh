#!/bin/sh
# Assert VNC is enabled for remote control over WiFi. The stock RealVNC
# service-mode unit (shipped by stage4's realvnc-vnc-server) must be enabled so
# it starts at boot and mirrors the X11 :0 autologin session. Operators connect
# over wlan0 or the zbitx AP (port 5900); auth is RealVNC's default SystemAuth
# (login as `pi` with the password set via Raspberry Pi Imager). Service mode
# needs the X11 session — guarded separately by the do_wayland W1 pin.
set -eu
UNIT=vncserver-x11-serviced.service

command -v vncserver-x11-serviced >/dev/null 2>&1 || {
    echo "FAIL: vncserver-x11-serviced not installed (realvnc-vnc-server missing from base?)" >&2
    exit 1
}

state=$(systemctl --root=/ is-enabled "$UNIT" 2>/dev/null || true)
case "$state" in
    enabled|enabled-runtime|static|alias) ;;
    *)
        echo "FAIL: $UNIT is '$state' (expected enabled)" >&2
        exit 1
        ;;
esac

echo "OK: VNC (RealVNC service mode) enabled at boot"
