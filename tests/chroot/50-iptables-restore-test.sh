#!/bin/sh
# Assert /etc/iptables/rules.v4 loads without error.
set -eu

if ! iptables-restore --test < /etc/iptables/rules.v4 2>/tmp/iptables-restore.log; then
    cat /tmp/iptables-restore.log >&2
    echo "FAIL: iptables-restore rejected rules.v4" >&2
    exit 1
fi
echo "OK: iptables rules.v4 parses"
