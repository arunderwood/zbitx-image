#!/bin/sh
# Assert all required apt packages installed.
set -eu

REQUIRED="hostapd dnsmasq sqlite3 libgtk-3-dev libsqlite3-dev libasound2-dev libncurses-dev iptables iptables-persistent dhcpcd5 wiringpi"

missing=""
for p in $REQUIRED; do
    if ! dpkg -s "$p" >/dev/null 2>&1; then
        missing="$missing $p"
    fi
done

if [ -n "$missing" ]; then
    echo "MISSING packages:$missing" >&2
    exit 1
fi
echo "OK: all required packages installed"
