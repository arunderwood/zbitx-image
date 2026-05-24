#!/bin/sh
# Runs once on the first boot of a flashed zbitx image, then disables itself.
# Steps that MUST happen on real hardware (not in the build chroot).
set -eu

LOG=/var/log/sbitx-firstboot.log
exec >>"$LOG" 2>&1
echo "=== sbitx-firstboot: $(date -u +%FT%TZ) ==="

mkdir -p /var/lib/sbitx

# ---- Regenerate SSH host keys ----
# Build-time keys are identical across every flashed image; replace them.
if [ -d /etc/ssh ] && command -v ssh-keygen >/dev/null 2>&1; then
    rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub
    dpkg-reconfigure -f noninteractive openssh-server || ssh-keygen -A
fi

# ---- Wipe build-time FFTW wisdom; let sbitx regenerate for THIS CPU ----
# The cache is CPU-tuned; baking it in produces sub-optimal plans.
rm -f /home/pi/sbitx/data/sbitx_wisdom.wis /home/pi/sbitx/data/sbitx_wisdom_f.wis 2>/dev/null || true

# ---- Set a unique machine ID ----
if [ -f /etc/machine-id ] && [ ! -s /etc/machine-id ]; then
    systemd-machine-id-setup
fi

# ---- Mark done + disable ----
touch /var/lib/sbitx/firstboot-done
systemctl disable sbitx-firstboot.service

echo "=== sbitx-firstboot: done ==="
