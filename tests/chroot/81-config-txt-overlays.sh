#!/bin/sh
# Assert /boot/firmware/config.txt actually got the zbitx overlay
# additions appended by os-config.sh. A silent failure here would
# brick the audio stack (no WM8731), I2C synthesizer, and snd-aloop
# WSJT-X bridge on real hardware — and the build itself wouldn't
# notice because rpi-image-gen doesn't validate config.txt contents.
set -eu

for path in /boot/firmware/config.txt /boot/config.txt; do
    if [ -f "$path" ]; then
        CONFIG_TXT=$path
        break
    fi
done

if [ -z "${CONFIG_TXT:-}" ]; then
    echo "FAIL: neither /boot/firmware/config.txt nor /boot/config.txt exists" >&2
    exit 1
fi

# All of these must be present for the radio to work.
missing=""
for line in \
    "dtoverlay=audioinjector-wm8731-audio" \
    "dtoverlay=i2s-mmap" \
    "dtparam=i2c_arm=on" \
    "dtparam=i2s=on" \
    "dtparam=audio=off"
do
    if ! grep -qE "^${line}\$" "$CONFIG_TXT"; then
        missing="$missing\n  $line"
    fi
done

if [ -n "$missing" ]; then
    printf "FAIL: %s missing lines:%b\n" "$CONFIG_TXT" "$missing" >&2
    exit 1
fi

echo "OK: $CONFIG_TXT has all required zbitx overlay lines"
