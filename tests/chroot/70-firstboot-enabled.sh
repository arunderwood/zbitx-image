#!/bin/sh
# Assert the firstboot one-shot service is installed and enabled.
set -eu

if ! systemctl --root=/ is-enabled sbitx-firstboot.service 2>/dev/null | grep -qx enabled; then
    echo "FAIL: sbitx-firstboot.service is not enabled" >&2
    systemctl --root=/ status sbitx-firstboot.service 2>&1 || true >&2
    exit 1
fi

if [ ! -x /usr/local/sbin/sbitx-firstboot.sh ]; then
    echo "FAIL: /usr/local/sbin/sbitx-firstboot.sh missing or not executable" >&2
    exit 1
fi

echo "OK: sbitx-firstboot service enabled"
