#!/bin/sh
# Assert the hostapd auto-restart drop-in is in place so the `zbitx` AP
# self-heals (e.g. if it races uap0.service at boot). The zBitx v2 WiFi front
# panel depends on this AP. Guards inventory §2.6
# (docs/reference-parity-inventory.md).
set -eu
D=/etc/systemd/system/hostapd.service.d/restart.conf

[ -f "$D" ] || { echo "FAIL: $D missing" >&2; exit 1; }
grep -q '^Restart=on-failure' "$D" || {
    echo "FAIL: $D missing 'Restart=on-failure'" >&2
    cat "$D" >&2
    exit 1
}
echo "OK: hostapd restart drop-in present (AP self-heals on failure)"
