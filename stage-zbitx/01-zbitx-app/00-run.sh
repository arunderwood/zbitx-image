#!/bin/bash -e
# Install WiringPi 3.x and build the zbitxv2 (sBitx) application into the
# rootfs at /home/${FIRST_USER_NAME}/sbitx. Runs on the host (pi-gen *-run.sh
# convention); reaches into the chroot with on_chroot for the compile steps.

# ---- WiringPi 3.x (Bookworm-port: replaces the deprecated drogon.net 2.x) ----
# Download on the host where the pinned URL/SHA env vars live, verify, then
# install inside the chroot via apt so its deps resolve.
curl -fsSL -o "${ROOTFS_DIR}/tmp/wiringpi.deb" "${ZBITX_WIRINGPI_URL}"
echo "${ZBITX_WIRINGPI_SHA256}  ${ROOTFS_DIR}/tmp/wiringpi.deb" | sha256sum -c -
on_chroot <<- EOF
	apt-get install -y /tmp/wiringpi.deb
	rm -f /tmp/wiringpi.deb
EOF

# ---- zbitxv2 source -> /home/${FIRST_USER_NAME}/sbitx + build ----
# sbitx hardcodes /home/pi/sbitx paths (sbitx.c, fft_filter.c), which is why
# FIRST_USER_NAME is pinned to `pi` in pi-gen.config. The account is left locked
# and 02-zbitx-os removes piwiz.desktop so first boot can't rename `pi` (we
# deliberately avoid DISABLE_FIRST_BOOT_USER_RENAME=1, which would force a baked
# password). ${ZBITX_SRCDIR} is the vendored submodule (set in pi-gen.config).
HOME_DIR="${ROOTFS_DIR}/home/${FIRST_USER_NAME}"
rm -rf "${HOME_DIR}/sbitx"
cp -a "${ZBITX_SRCDIR}" "${HOME_DIR}/sbitx"

install -m 0755 files/build-sbitx.sh "${ROOTFS_DIR}/tmp/build-sbitx.sh"
on_chroot <<- EOF
	/tmp/build-sbitx.sh
	rm -f /tmp/build-sbitx.sh
	chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME} /home/${FIRST_USER_NAME}/sbitx
EOF
