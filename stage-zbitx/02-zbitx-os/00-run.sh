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

# ---- Keep the user `pi` (protect sbitx's hardcoded /home/pi) ----
# We can't use DISABLE_FIRST_BOOT_USER_RENAME=1 (pi-gen requires a baked
# FIRST_USER_PASS for it). Removing the piwiz wizard is exactly what that
# path does internally: with no wizard, nothing on first boot renames `pi`.
# Raspberry Pi Imager's firstrun.sh still provisions password/WiFi/SSH.
rm -f "${ROOTFS_DIR}/etc/xdg/autostart/piwiz.desktop"

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

# ---- Disable HDMI audio so the WM8731 codec keeps ALSA card 0 ----
# sbitx hardcodes the codec as hw:0 / plughw:0,0. The stock vc4-kms-v3d overlay
# registers vc4hdmi as an ALSA card that grabs index 0, pushing the WM8731
# (audioinjectorpi) to a higher index; sbitx then opens the HDMI card, fails to
# find its mixer controls, and aborts (snd_mixer_selem_has_capture_switch on a
# NULL elem). `dtparam=audio=off` above only disables the legacy bcm2835 audio,
# not KMS HDMI audio. Appending ,noaudio drops the HDMI sound cards so the codec
# falls into the free index 0 (snd-aloop is pinned to 1,2,3). This is a
# workaround to match brittle hardcoding -- see UPSTREAM.md for the real fix.
if grep -qE '^[[:space:]]*dtoverlay=vc4-kms-v3d' "${CONFIG_TXT}" && \
   ! grep -qE '^[[:space:]]*dtoverlay=vc4-kms-v3d[^[:space:]]*noaudio' "${CONFIG_TXT}"; then
	sed -i -E 's/^([[:space:]]*dtoverlay=vc4-kms-v3d[^[:space:]]*)/\1,noaudio/' "${CONFIG_TXT}"
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
