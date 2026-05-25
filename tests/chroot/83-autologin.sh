#!/bin/sh
# Assert the autologin → startx → sBitx.desktop chain is wired up.
# This is what makes the radio's GUI actually appear on screen after
# a cold boot. Without these the system would boot to a tty1 login
# prompt with sbitx never running.
set -eu

# 1. tty1 autologin override
AUTOLOGIN=/etc/systemd/system/getty@tty1.service.d/autologin.conf
if [ ! -f "$AUTOLOGIN" ]; then
    echo "FAIL: $AUTOLOGIN missing" >&2
    exit 1
fi
if ! grep -qE 'agetty.*--autologin[[:space:]]+pi' "$AUTOLOGIN"; then
    echo "FAIL: $AUTOLOGIN doesn't autologin user 'pi'" >&2
    cat "$AUTOLOGIN" >&2
    exit 1
fi

# 2. /home/pi/.bash_profile must invoke startx on tty1
BP=/home/pi/.bash_profile
if [ ! -f "$BP" ]; then
    echo "FAIL: $BP missing" >&2
    exit 1
fi
if ! grep -q 'startx' "$BP"; then
    echo "FAIL: $BP doesn't invoke startx" >&2
    exit 1
fi

# 3. /home/pi/.xinitrc must exec openbox (which picks up XDG autostart)
XR=/home/pi/.xinitrc
if [ ! -x "$XR" ]; then
    echo "FAIL: $XR missing or not executable" >&2
    exit 1
fi
if ! grep -q 'openbox' "$XR"; then
    echo "FAIL: $XR doesn't exec openbox" >&2
    exit 1
fi

# 4. /etc/xdg/autostart/sBitx.desktop must Exec the radio binary
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

# 5. /home/pi/{,.bash_profile,.xinitrc} owned by pi:pi
for f in /home/pi/.bash_profile /home/pi/.xinitrc; do
    owner=$(stat -c '%U:%G' "$f" 2>/dev/null || echo "?")
    if [ "$owner" != "pi:pi" ]; then
        echo "FAIL: $f is owned by '$owner', expected 'pi:pi'" >&2
        exit 1
    fi
done

echo "OK: autologin → startx → openbox → sBitx autostart chain is wired"
