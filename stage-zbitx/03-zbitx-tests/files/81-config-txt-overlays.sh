#!/bin/sh
# Assert /boot/firmware/config.txt actually got the zbitx overlay
# additions appended by os-config.sh. A silent failure here would
# brick the audio stack (no WM8731), I2C synthesizer, and snd-aloop
# WSJT-X bridge on real hardware — and the build itself wouldn't
# notice because the build does not validate config.txt contents.
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

# HDMI audio must be disabled so the WM8731 codec keeps ALSA card 0 — sbitx
# hardcodes hw:0 and aborts if vc4hdmi steals index 0. See UPSTREAM.md.
if ! grep -qE "^[[:space:]]*dtoverlay=vc4-kms-v3d[^[:space:]]*noaudio" "$CONFIG_TXT"; then
    echo "FAIL: $CONFIG_TXT vc4-kms-v3d overlay missing 'noaudio' (HDMI audio would steal ALSA card 0 from the WM8731 codec)" >&2
    exit 1
fi

echo "OK: $CONFIG_TXT has all required zbitx overlay lines"
