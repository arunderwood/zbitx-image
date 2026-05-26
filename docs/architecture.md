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
  2. Copy the zbitxv2 source from `vendor/sbitx/` to `/home/pi/sbitx/`
     in the chroot, apply Bookworm patches, run `./build sbitx`,
     initialize the SQLite logbook, and seed `hw_settings.ini`.
  3. Lay down OS-level config (config.txt overlays, systemd units,
     hostapd/dnsmasq configs, iptables rules, autostart desktop file).
  4. Run the in-chroot smoke tests.

FFTW3 (double + single precision) comes from Debian Bookworm packages
(`libfftw3-dev` + `libfftw3-single3`), which currently track upstream
3.3.10. Earlier iterations built it from source per upstream's
`install.txt` — that step is gone because the packaged version is
identical.

### `layer/scripts/`

Bash helpers invoked by the layer's hooks. Kept out of the YAML to
keep the manifest readable:

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
- Expected boot units (`uap0`, `hostapd`, `dnsmasq`,
  `netfilter-persistent`, `lightdm`) are enabled.
- Desktop audio stack (`pipewire.socket`, `pipewire-pulse.socket`,
  `wireplumber.service`, `pulseaudio.socket`) is masked so it
  doesn't grab the WM8731 ALSA card out from under sbitx.

What's NOT tested at build time: anything requiring real GPIO/I2C
hardware, the WM8731 codec, the actual radio path, or the kernel /
Pi firmware boot path. Those are real-hardware-only territory —
flash and validate per the checklist in `docs/bookworm-patches.md`.

### What about QEMU?

A previous iteration attempted a Tier-2 QEMU boot test
(`qemu-system-aarch64 -M raspi3b`) against the produced image, but
QEMU 8.x's raspi3b emulation is too incomplete to reliably boot an
off-the-shelf Pi OS image to a serial-visible login prompt — the
known limitation is around the Pi firmware (start.elf, bootcode.bin,
GPU dance) and serial-console setup. QEMU 9/10/11 release notes
don't call out fixes for this. The QEMU test was removed.

The path that genuinely works for "does it boot?" is real-hardware
flash, which lives outside CI.

### `.github/workflows/build.yml`

GHA workflow. Runs on `ubuntu-24.04-arm` (free for public repos
since 2025), installs rpi-image-gen's host deps, builds the image,
and uploads both the `.img.zst` and the SBOM as artifacts.

### Submodules

- `rpi-image-gen/` — pinned to v2.6.0.
- `vendor/sbitx/` — pinned to the zbitxv2 SHA that was current when
  the recipe was scaffolded. Bump explicitly when picking up new
  application changes; each bump is a commit you can review.

## Build-time state hygiene

A handful of files would be a security/correctness smell if shipped
identical across every flashed image. Rather than carry a firstboot
script to clean them up after the fact, the build's `cleanup-hooks`
delete them so they're absent from the image and regenerated
naturally on first boot:

- **SSH host keys** (`/etc/ssh/ssh_host_*_key*`) — removed at
  cleanup. sshd's first start on real hardware regenerates fresh
  per-device keys.
- **machine-id** (`/etc/machine-id`, `/var/lib/dbus/machine-id`) —
  truncated/removed. `systemd-machine-id-setup` regenerates on first
  boot.
- **FFTW wisdom** (`/home/pi/sbitx/data/sbitx_wisdom*.wis`) — the
  upstream tree commits these; `build-sbitx.sh` deletes them after
  the source copy. FFTW generates fresh wisdom on first `sbitx` run.

Rootfs expansion on first boot is handled by stock Pi OS
(`init_resize.sh`).
