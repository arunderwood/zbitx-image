#!/usr/bin/env bash
# Mount the official hand-built zBitx v2 reference image read-only so its
# rootfs and boot partition can be inspected and compared against what this
# recipe produces.
#
# The reference image is the maintainer's hand-crafted image that this build
# is trying to recreate. It is NEVER modified: the loop device and both
# mounts are read-only, so nothing here can alter the downloaded artifact.
#
# This script runs inside the WSL "Debian" distro (Linux can loop-mount the
# image's ext4 rootfs; Windows cannot). See docs/inspecting-the-reference-image.md.
#
# Usage (from the Windows side):
#     wsl -d Debian -- /mnt/c/Users/daniel/checkouts/zbitxv2-image/scripts/inspect-reference-image.sh up
#     wsl -d Debian -- /mnt/c/Users/daniel/checkouts/zbitxv2-image/scripts/inspect-reference-image.sh status
#     wsl -d Debian -- /mnt/c/Users/daniel/checkouts/zbitxv2-image/scripts/inspect-reference-image.sh down
#
# Override the source .gz with ZBITX_REF_GZ=/path/to/image.img.gz
set -euo pipefail

GZ="${ZBITX_REF_GZ:-/mnt/c/Users/daniel/Downloads/zbitxv2.img.gz}"
WORKDIR="${ZBITX_REF_WORKDIR:-/root/zbitx-ref}"
IMG="${WORKDIR}/zbitxv2.img"
BOOT_MNT="/mnt/ref-boot"
ROOT_MNT="/mnt/ref-root"

die() { echo "error: $*" >&2; exit 1; }

# Loop device currently backing the image, if any (empty string otherwise).
find_loop() { losetup -j "$IMG" 2>/dev/null | cut -d: -f1 | head -n1; }

cmd_up() {
	[ "$(id -u)" -eq 0 ] || die "must run as root (use: wsl -d Debian -u root ...)"
	mkdir -p "$WORKDIR"

	if [ ! -f "$IMG" ]; then
		[ -f "$GZ" ] || die "compressed image not found: $GZ"
		echo "Decompressing $GZ -> $IMG (one-time, a few minutes) ..."
		gunzip -c "$GZ" > "$IMG"
	fi

	local loop
	loop="$(find_loop)"
	if [ -z "$loop" ]; then
		# --partscan exposes ${loop}p1/${loop}p2; --read-only protects the image.
		loop="$(losetup --find --partscan --read-only --show "$IMG")"
	fi
	[ -n "$loop" ] || die "could not attach loop device"

	mkdir -p "$BOOT_MNT" "$ROOT_MNT"
	# boot is FAT32; rootfs is ext4 (noload skips journal replay on the RO device).
	mountpoint -q "$BOOT_MNT" || mount -o ro "${loop}p1" "$BOOT_MNT"
	mountpoint -q "$ROOT_MNT" || mount -o ro,noload "${loop}p2" "$ROOT_MNT"

	cmd_status
}

cmd_status() {
	local loop
	loop="$(find_loop)"
	if [ -z "$loop" ]; then
		echo "reference image not attached (run: $0 up)"
		return 0
	fi
	echo "Reference image mounted read-only:"
	echo "  source : $GZ"
	echo "  image  : $IMG ($loop)"
	mountpoint -q "$BOOT_MNT" && echo "  boot   : $BOOT_MNT   (${loop}p1, FAT32)"
	mountpoint -q "$ROOT_MNT" && echo "  rootfs : $ROOT_MNT   (${loop}p2, ext4)"
}

cmd_down() {
	mountpoint -q "$BOOT_MNT" && umount "$BOOT_MNT" || true
	mountpoint -q "$ROOT_MNT" && umount "$ROOT_MNT" || true
	local loop
	loop="$(find_loop)"
	[ -n "$loop" ] && losetup -d "$loop" || true
	echo "Reference image detached. (Decompressed $IMG kept for next time;"
	echo "delete it manually to reclaim disk: rm $IMG)"
}

case "${1:-}" in
	up)     cmd_up ;;
	status) cmd_status ;;
	down)   cmd_down ;;
	*)      echo "usage: $0 {up|status|down}" >&2; exit 2 ;;
esac
