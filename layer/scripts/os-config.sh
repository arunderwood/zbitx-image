#!/bin/sh
# OS-level configuration applied inside the chroot.
# File overlays (hostapd.conf, dnsmasq config, systemd units, etc.) are
# laid down by the calling hook via tar -x. This script handles steps
# that need shell logic.
set -eux

# ---- /boot/firmware/config.txt — append zbitx overlays ----
# rpi-image-gen's image-rpios layout puts config.txt at /boot/firmware/.
CONFIG_TXT=/boot/firmware/config.txt
if [ ! -f "$CONFIG_TXT" ]; then
    CONFIG_TXT=/boot/config.txt
fi

if ! grep -q "# zbitx-sbitx BEGIN" "$CONFIG_TXT" 2>/dev/null; then
    cat >> "$CONFIG_TXT" <<'EOF'

# zbitx-sbitx BEGIN -- managed by zbitxv2-image
gpio=4,5,9,10,11,17,22,27=ip,pu
gpio=24,23=op,pu
dtoverlay=audioinjector-wm8731-audio
dtoverlay=i2s-mmap
dtparam=i2c_arm=on
dtparam=i2s=on
avoid_warnings=1
# Disable built-in audio (the WM8731 codec is primary).
# (Stock raspi config sets dtparam=audio=on; we override.)
dtparam=audio=off
# zbitx-sbitx END
EOF
fi

# ---- PulseAudio bypass (install.txt:44-50) ----
# Bookworm's PulseAudio shim is harmless if absent; defensive write.
mkdir -p /etc/pulse
if [ -f /etc/pulse/client.conf ]; then
    if ! grep -q "^autospawn = no" /etc/pulse/client.conf; then
        printf "\nautospawn = no\ndaemon-binary = /bin/true\n" >> /etc/pulse/client.conf
    fi
fi

# ---- iptables NAT redirect (port 80 → 8080) loaded by iptables-persistent ----
# Rules file is dropped by the overlay; ensure permissions.
if [ -f /etc/iptables/rules.v4 ]; then
    chmod 0644 /etc/iptables/rules.v4
fi

# ---- Add `pi` user to the audio/i2c/gpio groups ----
# rpi-user-credentials creates `pi`; we ensure group memberships.
for g in audio i2c gpio video plugdev dialout input; do
    if getent group "$g" >/dev/null 2>&1; then
        usermod -a -G "$g" pi 2>/dev/null || true
    fi
done

# ---- Set autologin via raspi-config's nonint API ----
# `raspi-config nonint do_boot_behaviour B4` configures lightdm to
# autologin to the desktop session. Our drop-in
# /etc/lightdm/lightdm.conf.d/50-zbitx-autologin.conf has the same
# effect and is more transparent; raspi-config call is belt-and-braces.
# (Skipped if raspi-config isn't available in this chroot for any reason.)
if command -v raspi-config >/dev/null 2>&1; then
    raspi-config nonint do_boot_behaviour B4 || true
fi

# ---- Ensure /usr/local/lib is in ld.so.cache (FFTW lives here) ----
# rpi-image-gen's base ld.so.conf usually has /usr/local/lib already,
# but be defensive.
if [ -d /etc/ld.so.conf.d ] && ! grep -hq '^/usr/local/lib' /etc/ld.so.conf /etc/ld.so.conf.d/*.conf 2>/dev/null; then
    echo /usr/local/lib > /etc/ld.so.conf.d/local-fftw.conf
fi
ldconfig

echo "os-config.sh: complete"
