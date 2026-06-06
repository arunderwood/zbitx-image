#!/bin/bash -e
# Copy the previous stage's rootfs (stage4 = Raspberry Pi OS Desktop) forward
# so stage-zbitx layers the zbitx delta on top of it. Mirrors every stock
# pi-gen stage's prerun.sh.

if [ ! -d "${ROOTFS_DIR}" ]; then
	copy_previous
fi
