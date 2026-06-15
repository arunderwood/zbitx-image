#!/bin/sh
# Assert the zbitx-owned boot units are enabled.
# `systemctl is-enabled` in a chroot reads the symlink graph under
# /etc/systemd/system/*.wants/ — it works without a running PID 1.
#
# Narrowed for the pi-gen base: lightdm (desktop) and resize2fs_once (rootfs
# expansion) are now enabled by stock stages, not us, so they are out of scope
# here. The old zbitx-expand-rootfs.service no longer exists (init_resize does
# the job). This test covers only the units stage-zbitx enables.
set -eu

failed=""
for unit in uap0.service hostapd.service dnsmasq.service netfilter-persistent.service \
            zbitx-ap-follow-channel.timer; do
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

echo "OK: all expected zbitx boot units enabled"
