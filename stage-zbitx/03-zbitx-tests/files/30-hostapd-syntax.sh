#!/bin/sh
# Assert hostapd.conf is present and has the expected key/value lines.
# We deliberately avoid invoking hostapd itself: there is no portable
# "syntax check only" mode, and any invocation requires a wlan device.
set -eu

CONF=/etc/hostapd/hostapd.conf
if [ ! -r "$CONF" ]; then
    echo "FAIL: $CONF missing or unreadable" >&2
    exit 1
fi

# Required keys for the zbitx AP setup
missing=""
for key in interface ssid hw_mode channel wpa wpa_passphrase wpa_key_mgmt; do
    if ! grep -qE "^${key}=" "$CONF"; then
        missing="$missing $key"
    fi
done

if [ -n "$missing" ]; then
    echo "FAIL: missing required hostapd.conf keys:$missing" >&2
    exit 1
fi

# Spot-check the SSID we expect
if ! grep -qE '^ssid=zbitx$' "$CONF"; then
    echo "FAIL: expected 'ssid=zbitx' in $CONF" >&2
    grep '^ssid=' "$CONF" >&2 || true
    exit 1
fi

echo "OK: hostapd.conf has all required keys"
