#!/bin/sh
# Assert the AudioInjector WM8731 dtoverlay ships in Bookworm's raspi-firmware.
# This is the most likely first failure point on a new OS release.
set -eu

for path in \
    /boot/overlays/audioinjector-wm8731-audio.dtbo \
    /boot/firmware/overlays/audioinjector-wm8731-audio.dtbo
do
    if [ -f "$path" ]; then
        echo "OK: found $path"
        exit 0
    fi
done

echo "FAIL: audioinjector-wm8731-audio.dtbo NOT FOUND in /boot or /boot/firmware overlays" >&2
echo "       (this overlay is required for the WM8731 audio codec on the sBitx board)" >&2
ls -la /boot/overlays/ 2>/dev/null >&2 || true
ls -la /boot/firmware/overlays/ 2>/dev/null >&2 || true
exit 1
