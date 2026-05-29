#!/bin/sh
# Assert every systemd unit we expect to fire at boot is enabled.
# `systemctl is-enabled` in a chroot reads the symlink graph under
# /etc/systemd/system/*.wants/ — it works without a running PID 1.
set -eu

failed=""
for unit in uap0.service hostapd.service dnsmasq.service netfilter-persistent.service lightdm.service zbitx-expand-rootfs.service; do
    state=$(systemctl --root=/ is-enabled "$unit" 2>/dev/null || true)
    case "$state" in
        enabled|enabled-runtime|static|alias) ;;
        *)
            echo "FAIL: $unit is '$state' (expected enabled)" >&2
            failed="$failed $unit"
            ;;
    esac
done

if [ -n "$failed" ]; then
    echo "FAIL: not enabled:$failed" >&2
    exit 1
fi

echo "OK: all expected boot units enabled"
