#!/usr/bin/env bash
# Build the zbitx image with pi-gen.
#
# This repo keeps stage-zbitx and pi-gen.config outside the pinned pi-gen
# submodule (vendor/pi-gen). This wrapper wires them in:
#   * exports ZBITX_ROOT so pi-gen.config's STAGE_LIST can point at the
#     external stage-zbitx;
#   * drops a SKIP_IMAGES marker in stage2 and stage4 so pi-gen does NOT
#     export the stock -lite and Desktop images — only stage-zbitx emits one;
#   * runs pi-gen's build.sh as root with our config.
#
# Native build only (build.sh, not Docker). On a native arm64 host (e.g. the
# CI `ubuntu-24.04-arm` runner, or a Pi) nothing extra is needed. On an x86_64
# host (e.g. WSL) install `qemu-user-static` + `binfmt-support` first so the
# arm64 chroot can run, or build on arm64 hardware.
#
# Usage:  ./scripts/pi-gen-build.sh
#         CLEAN=1 ./scripts/pi-gen-build.sh     # discard cached stage rootfs
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIGEN="${REPO_ROOT}/vendor/pi-gen"

# Ensure the submodules are checked out (pi-gen tooling + sbitx source).
if [ ! -f "${PIGEN}/build.sh" ] || [ ! -e "${REPO_ROOT}/vendor/sbitx/build" ]; then
	echo "==> Initialising submodules"
	git -C "${REPO_ROOT}" submodule update --init --recursive
fi

# Suppress the stock intermediate image exports (stage2 = -lite, stage4 =
# Desktop). These markers live in the submodule working tree, are build-time
# only, and are not tracked by this repo.
touch "${PIGEN}/stage2/SKIP_IMAGES" "${PIGEN}/stage4/SKIP_IMAGES"

# Consumed by pi-gen.config (STAGE_LIST) to locate the external stage.
export ZBITX_ROOT="${REPO_ROOT}"

echo "==> Building zbitx image via pi-gen ($(git -C "${PIGEN}" rev-parse --short HEAD))"
cd "${PIGEN}"
exec sudo --preserve-env=ZBITX_ROOT,CLEAN,CONTINUE,USE_QEMU,APT_PROXY,DEPLOY_COMPRESSION,COMPRESSION_LEVEL \
	./build.sh -c "${REPO_ROOT}/pi-gen.config"
