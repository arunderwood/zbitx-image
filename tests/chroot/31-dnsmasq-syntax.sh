#!/bin/sh
# Assert dnsmasq's uap0 drop-in is syntactically valid.
set -eu

if ! dnsmasq --test --conf-file=/etc/dnsmasq.d/uap0.conf 2>&1 | grep -q 'syntax check OK'; then
    dnsmasq --test --conf-file=/etc/dnsmasq.d/uap0.conf >&2
    echo "FAIL: dnsmasq config syntax check failed" >&2
    exit 1
fi
echo "OK: dnsmasq uap0.conf parses"
