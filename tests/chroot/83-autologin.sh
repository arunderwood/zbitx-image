#!/bin/sh
# Assert lightdm is set up to autologin the `pi` user, which in turn
# starts the desktop session, which fires /etc/xdg/autostart/sBitx.desktop
# and launches the radio GUI. This matches `raspi-config`'s "Desktop
# with autologin" mode (B4).
set -eu

# 1. lightdm must be installed (it's the display manager that does autologin)
if ! command -v lightdm >/dev/null 2>&1 && [ ! -x /usr/sbin/lightdm ]; then
    echo "FAIL: lightdm not installed" >&2
    exit 1
fi

# 2. Our autologin drop-in must be present and reference user 'pi'
DROPIN=/etc/lightdm/lightdm.conf.d/50-zbitx-autologin.conf
if [ ! -f "$DROPIN" ]; then
    echo "FAIL: $DROPIN missing" >&2
    exit 1
fi
if ! grep -qE '^autologin-user=pi[[:space:]]*$' "$DROPIN"; then
    echo "FAIL: $DROPIN doesn't set 'autologin-user=pi'" >&2
    cat "$DROPIN" >&2
    exit 1
fi

# 3. lightdm.service must be enabled (so it starts at boot)
state=$(systemctl --root=/ is-enabled lightdm.service 2>/dev/null || true)
case "$state" in
    enabled|enabled-runtime|static|alias) ;;
    *)
        echo "FAIL: lightdm.service is '$state' (expected enabled)" >&2
        exit 1
        ;;
esac

# 4. The XDG autostart entry that actually launches sbitx
SD=/etc/xdg/autostart/sBitx.desktop
if [ ! -f "$SD" ]; then
    echo "FAIL: $SD missing" >&2
    exit 1
fi
if ! grep -qE '^Exec=/home/pi/sbitx/sbitx' "$SD"; then
    echo "FAIL: $SD doesn't launch /home/pi/sbitx/sbitx" >&2
    grep '^Exec=' "$SD" >&2 || true
    exit 1
fi

echo "OK: lightdm autologin → desktop session → sBitx.desktop chain wired"
