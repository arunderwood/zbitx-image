#!/bin/sh
# Assert the `pi` user is in the groups the radio needs for hardware
# access. Without these, sbitx running unprivileged can't open
# /dev/snd/*, /dev/i2c-*, GPIO sysfs, /dev/video*, etc.
set -eu

if ! id pi >/dev/null 2>&1; then
    echo "FAIL: user 'pi' does not exist" >&2
    exit 1
fi

GROUPS_OUT=$(id -nG pi)
missing=""
# audio: ALSA device access (the WM8731 codec)
# i2c:   /dev/i2c-* for the si5351/si570/OLED
# gpio:  /sys/class/gpio for relay control + PTT
# video: required by some GTK rendering paths on Pi hw
# dialout: serial port (CAT, swr bridge)
# plugdev: removable storage (USB sticks for file transfer)
for g in audio i2c gpio video dialout plugdev; do
    case " $GROUPS_OUT " in
        *" $g "*) ;;
        *) missing="$missing $g";;
    esac
done

if [ -n "$missing" ]; then
    echo "FAIL: pi user missing groups:$missing (has: $GROUPS_OUT)" >&2
    exit 1
fi

echo "OK: pi user in expected groups ($GROUPS_OUT)"
