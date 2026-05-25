# Architecture

How the recipe is organized and what each piece does.

## rpi-image-gen primer

rpi-image-gen composes three abstractions to produce an image:

- **Configuration** (`config/<name>.yaml`) — top-level entry point.
  Declares the device, image layout, and root layer to build.
- **Layers** (`layer/<name>.yaml`) — modular composable units. A
  layer has a `METABEGIN`/`METAEND` comment header declaring its
  name, dependencies, and variables, followed by an `mmdebstrap:`
  section with apt packages and lifecycle hooks.
- **Hooks** — shell commands invoked at defined points in the
  rootfs build. `setup-hooks` run before the chroot is built;
  `customize-hooks` run after packages are installed (this is where
  most of our work happens); `cleanup-hooks` run last.

Build invocation:

```
rpi-image-gen build -S <project-dir> -c <config-basename>.yaml
```

Output lands at `./work/<image-name>/<image-name>.img.zst`.

## This repo's structure

### `config/zbitx-bookworm.yaml`

The top-level config. Pins:

- `device.layer: rpizero2w` — built-in device layer for Pi Zero 2 W
  (arm64).
- `image.layer: image-rpios` — standard Raspberry Pi OS partition
  layout (FAT32 boot + ext4 root).
- `layer.app: zbitx-sbitx` — points at our custom layer.

### `layer/zbitx-sbitx.yaml`

The custom layer. Declares:

- Build-toolchain and runtime apt packages (replacing `ntp`/`ntpstat`
  with `systemd-timesyncd`, which is default-present on Bookworm).
- A list of `customize-hooks` that:
  1. Install WiringPi 3.x from a downloaded `.deb`.
  2. Build FFTW3 (double + single precision) from source.
  3. Copy the zbitxv2 source from `vendor/sbitx/` to `/home/pi/sbitx/`
     in the chroot, apply Bookworm patches, run `./build sbitx`,
     initialize the SQLite logbook, and seed `hw_settings.ini`.
  4. Lay down OS-level config (config.txt overlays, systemd units,
     hostapd/dnsmasq configs, iptables rules, autostart desktop file).
  5. Run the in-chroot smoke tests.

### `layer/scripts/`

Bash helpers invoked by the layer's hooks. Kept out of the YAML to
keep the manifest readable:

- `build-fftw.sh` — downloads, verifies, and builds FFTW.
- `build-sbitx.sh` — applies in-source patches and runs the build.
- `os-config.sh` — appends to `config.txt`, sets group memberships,
  defensively configures PulseAudio bypass.

### `layer/files/`

Static file overlays copied into the rootfs. Mirrors the destination
tree (`etc/`, `boot/`, `usr/`) so the mapping is obvious.

### `tests/chroot/`

Smoke tests run inside the chroot at the tail of the customize-hooks.
Each is a small shell script that asserts one property; the layer
fails the build if any test exits non-zero. Tests cover:

- All required apt packages installed.
- `sbitx` binary links cleanly (no unresolved shared libraries).
- `hostapd.conf` and `dnsmasq` configs are syntactically valid.
- SQLite logbook DB exists and has the expected schema.
- `iptables-restore --test` accepts the rules file.
- AudioInjector dtoverlay ships in Bookworm's raspi-firmware.
- `sbitx-firstboot.service` is enabled.

What's NOT tested at build time: anything requiring real GPIO/I2C
hardware, the WM8731 codec, or the actual radio path. That's
real-hardware validation, gated separately.

### Tier 2 (best-effort): QEMU raspi3b boot

There's also a Tier-2 QEMU boot test that attempts to boot the produced
`.img` in `qemu-system-aarch64 -M raspi3b`. **It is not a CI gate** —
QEMU 8.x's raspi3b emulation is incomplete (no USB, no network, partial
Pi firmware support) and reliably booting an off-the-shelf RPi OS image
in it doesn't work in our environment: the kernel never gets serial
console output up, whether we use `-kernel` directly or let the SD
firmware chain-load. The step stays in CI because if a future QEMU
release fixes this, the harness is ready — but a failure does not
block the artifact upload or fail the job. The qemu-log artifact is
still uploaded so anyone debugging can see the partial output.

For full-system boot validation, real hardware flash is the gate
(documented in `docs/bookworm-patches.md`).

### `.github/workflows/build.yml`

GHA workflow. Runs on `ubuntu-24.04-arm` (free for public repos
since 2025), installs rpi-image-gen's host deps, builds the image,
and uploads both the `.img.zst` and the SBOM as artifacts.

### Submodules

- `rpi-image-gen/` — pinned to v2.6.0.
- `vendor/sbitx/` — pinned to the zbitxv2 SHA that was current when
  the recipe was scaffolded. Bump explicitly when picking up new
  application changes; each bump is a commit you can review.

## First-boot deferral

A handful of steps can't happen in the build chroot and run instead
via a one-shot systemd service (`sbitx-firstboot.service`) at first
boot:

- Regenerate SSH host keys (chroot-baked keys are identical across
  every flashed image — a security smell).
- Delete build-time FFTW wisdom files so sbitx generates plans
  optimized for the actual CPU on first launch.
- Set a unique machine-id if missing.

The service self-disables after success via
`ConditionPathExists=!/var/lib/sbitx/firstboot-done`, mirroring the
canonical Raspberry Pi pattern (`raspi-config`'s `do_resize`).
