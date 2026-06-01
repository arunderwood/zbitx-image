#!/bin/bash -e
# Run the zbitx in-chroot smoke tests as the final gate of stage-zbitx. Any
# non-zero test fails the build. These assert zbitx-specific properties only;
# generic Raspberry Pi OS correctness is the base image's responsibility.

install -d "${ROOTFS_DIR}/tmp/zbitx-tests"
install -m 0755 files/*.sh "${ROOTFS_DIR}/tmp/zbitx-tests/"

on_chroot <<-'EOF'
	set -e
	for t in /tmp/zbitx-tests/*.sh; do
		echo "== ${t} =="
		"${t}"
	done
EOF

rm -rf "${ROOTFS_DIR}/tmp/zbitx-tests"
