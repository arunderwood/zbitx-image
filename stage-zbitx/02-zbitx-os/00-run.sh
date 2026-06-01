#!/bin/bash -e
# Lay down zbitx OS configuration on top of Raspberry Pi OS Desktop and enable
# the zbitx services. Runs on the host; uses on_chroot for in-chroot steps.
#
# Deliberately NOT done here (inherited from stock pi-gen stages, no longer
# our job):
#   - user group membership      -> stage2 adds pi to audio/i2c/gpio/spi/video/...
#   - desktop autologin          -> stage4 runs `raspi-config do_boot_behaviour B4`
#   - first-boot rootfs expansion -> stage2 enables resize2fs_once
#   - SSH host key / machine-id hygiene -> stage2 + regenerate_ssh_host_keys

# ---- File overlays (hostapd/dnsmasq/uap0/iptables/snd-aloop/autostart/NM) ----
cp -a files/rootfs/. "${ROOTFS_DIR}/"

# ---- config.txt: zbitx hardware overlays ----
CONFIG_TXT="${ROOTFS_DIR}/boot/firmware/config.txt"
[ -f "${CONFIG_TXT}" ] || CONFIG_TXT="${ROOTFS_DIR}/boot/config.txt"
if ! grep -q "# zbitx-sbitx BEGIN" "${CONFIG_TXT}" 2>/dev/null; then
	cat >> "${CONFIG_TXT}" <<-'EOF'

		# zbitx-sbitx BEGIN -- managed by zbitxv2-image
		gpio=4,5,9,10,11,17,22,27=ip,pu
		gpio=24,23=op,pu
		dtoverlay=audioinjector-wm8731-audio
		dtoverlay=i2s-mmap
		dtparam=i2c_arm=on
		dtparam=i2s=on
		avoid_warnings=1
		# Disable built-in audio (the WM8731 codec is primary).
		dtparam=audio=off
		# zbitx-sbitx END
	EOF
fi

# ---- iptables rules: enforce mode (overlay tar can lose it) ----
for f in "${ROOTFS_DIR}/etc/iptables/rules.v4" "${ROOTFS_DIR}/etc/iptables/rules.v6"; do
	[ -f "$f" ] && chmod 0644 "$f"
done

# ---- PulseAudio autospawn bypass (belt-and-braces with the masking below) ----
if [ -f "${ROOTFS_DIR}/etc/pulse/client.conf" ] && \
   ! grep -q "^autospawn = no" "${ROOTFS_DIR}/etc/pulse/client.conf"; then
	printf "\nautospawn = no\ndaemon-binary = /bin/true\n" >> "${ROOTFS_DIR}/etc/pulse/client.conf"
fi

on_chroot <<-EOF
	# ---- Force the X11/openbox Pixel session ----
	# stage4 defaults the desktop to labwc/Wayland (do_wayland W3). sbitx is a
	# GTK3/X11 app launched via /etc/xdg/autostart (honoured by openbox+lxsession,
	# not by the wlroots labwc session), and the audio masking below assumes the
	# X session's stack. Pin X11 (W1) — a stock raspi-config option, not a hack.
	SUDO_USER="${FIRST_USER_NAME}" raspi-config nonint do_wayland W1

	# ---- Free the WM8731 ALSA card from the desktop audio stack ----
	# sbitx opens the codec directly via ALSA (hw:0,0) plus the snd-aloop virtual
	# cards. raspberrypi-ui-mods pulls pipewire/pulseaudio (via the volume applet);
	# socket-activated, they would grab the card. Mask them for every user.
	systemctl --global mask \
		pipewire.socket pipewire-pulse.socket \
		wireplumber.service \
		pulseaudio.socket pulseaudio.service || true

	# ---- Enable the zbitx AP services ----
	# NetworkManager keeps wlan0 (client); uap0.service builds the virtual AP
	# interface; hostapd+dnsmasq serve it. NM leaves uap0 alone via the
	# 99-zbitx-uap0-unmanaged.conf overlay. dhcpcd is not used.
	systemctl unmask hostapd || true
	systemctl enable uap0.service hostapd dnsmasq
EOF
