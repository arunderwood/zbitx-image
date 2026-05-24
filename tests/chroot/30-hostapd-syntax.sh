#!/bin/sh
# Assert hostapd.conf parses cleanly.
set -eu

# `hostapd -t` exits non-zero on syntax error. Even without an interface,
# the config-parse stage is exercised.
if ! hostapd -t /etc/hostapd/hostapd.conf 2>&1 | tee /tmp/hostapd-syntax.log | grep -qE '^Configuration file:'; then
    cat /tmp/hostapd-syntax.log >&2
    echo "FAIL: hostapd refused /etc/hostapd/hostapd.conf" >&2
    exit 1
fi
echo "OK: hostapd.conf parses"
