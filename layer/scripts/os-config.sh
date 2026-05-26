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

# ---- Stop the desktop audio stack from grabbing the WM8731 ALSA card ----
# sbitx talks directly to ALSA (hw:0,0 for the WM8731, hw:1/2/3 for the
# snd-aloop virtual cards). If PipeWire or PulseAudio is running under
# the pi desktop session, it grabs the codec via its ALSA backend and
# sbitx cannot open the device.
#
# raspberrypi-ui-mods pulls in pipewire + pipewire-pulse + wireplumber +
# pulseaudio transitively (via the lxplug-volumepulse / wfplug-volumepulse
# Recommends chain). Their user units are socket-activated in
# /etc/systemd/user/sockets.target.wants/ — anyone hitting libpulse's
# socket triggers the daemon. Mask them globally so they never start
# for any user; symlinks land at /etc/systemd/user/<unit> -> /dev/null.
systemctl --global mask \
    pipewire.socket \
    pipewire-pulse.socket \
    wireplumber.service \
    pulseaudio.socket \
    pulseaudio.service 2>/dev/null || true

# Belt-and-braces: the upstream install.txt:44-50 bypass for libpulse
# clients that try to autospawn the daemon despite the masked socket.
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

# ---- Autologin ----
# Configured declaratively via /etc/lightdm/lightdm.conf.d/50-zbitx-autologin.conf
# (laid down by the file overlay). Equivalent to
# `raspi-config nonint do_boot_behaviour B4`.

echo "os-config.sh: complete"
