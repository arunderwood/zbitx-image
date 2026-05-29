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

Output lands at `./work/deploy-<version>/<image-name>.img.zst`,
where `<version>` comes from `git describe --tags --always --dirty`
(falls back to today's date outside a git checkout).

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
- `/etc/iptables/rules.v4` is structurally valid (required tables,
  COMMITs, and the 80→8080 REDIRECT rule). The full
  `iptables-restore --test` can't run inside an mmdebstrap chroot
  because the kernel namespace lacks `CAP_NET_ADMIN`; the live rules
  are validated at first boot when `iptables-persistent` loads them.
- AudioInjector dtoverlay ships in Bookworm's raspi-firmware.
- Expected boot units (`uap0`, `hostapd`, `dnsmasq`,
  `netfilter-persistent`, `lightdm`) are enabled.
- `pi` user is in the audio/gpio/i2c/spi groups.
- `config.txt` contains the AudioInjector dtoverlay + the GPIO/I2C/I2S
  enable lines.
- The ld.so cache resolves `libfftw3` / `libfftw3f`.
- lightdm autologin is configured for the `pi` user.
- Desktop audio stack (`pipewire.socket`, `pipewire-pulse.socket`,
  `wireplumber.service`, `pulseaudio.socket`) is masked so it
  doesn't grab the WM8731 ALSA card out from under sbitx.

What's NOT tested at build time: anything requiring real GPIO/I2C
hardware, the WM8731 codec, the actual radio path, or the kernel /
Pi firmware boot path. Those are real-hardware-only territory —
flash and validate per the checklist in `docs/bookworm-patches.md`.

### Tier-1 boot validation: systemd-nspawn

After the image build succeeds, CI boots the produced rootfs as a
systemd-nspawn container and confirms PID 1 reaches
`multi-user.target` within 90 seconds. This catches dynamic
failures that the static in-chroot tests can't see: service
ordering bugs, D-Bus startup issues, lightdm crash-loops, broken
user/shell setup, and similar.

Limits: nspawn shares the host kernel, so kernel module loading
(`snd-aloop`, dtoverlays) and any hardware-touching code (I2C,
GPIO, WM8731 audio) are not exercised. The boot log is uploaded
as the `nspawn-log` artifact and tailed into the run's step
summary on every run.

### What about QEMU?

A previous iteration attempted a Tier-2 QEMU boot test against the
produced SD image. QEMU's `raspi3b`/`raspi4b` machines are too
incomplete to reliably boot an off-the-shelf Pi OS image to a
serial-visible login prompt (Pi firmware / GPU init, serial-console
setup). After several iterations trying to make it stable, the
QEMU test was removed. Real-hardware flash is the path that
genuinely works for "does it boot?", and lives outside CI.

### `.github/workflows/build.yml`

GHA workflow. Runs on `ubuntu-24.04-arm` (free for public repos
since 2025), installs rpi-image-gen's host deps, builds the image,
runs the Tier-1 nspawn boot test, and uploads the `.img.zst`, the
SBOM, the build log, and the nspawn log as artifacts.

### External tools and submodules

- **rpi-image-gen** is not vendored. The pinned version is the
  `RPI_IMAGE_GEN_REF` env var in `.github/workflows/build.yml`; CI
  clones it shallowly into `$RUNNER_TEMP` and passes `-S "$PWD"` so
  the recipe's `config/` and `layer/` are read from this repo without
  touching the tool's tree. Local builders do the same — see the
  README "Building locally" section. This matches upstream's intended
  usage (the `-S` flag exists for exactly this) and keeps a ~100 MB
  unrelated toolchain out of every clone of this repo.
- `vendor/sbitx/` is a submodule pinned to the zbitxv2 SHA that was
  current when the recipe was scaffolded. Bump explicitly when picking
  up new application changes; each bump is a commit you can review.

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

## First-boot rootfs expansion

`image-rpios` (rpi-image-gen's `mbr/simple_dual` layout) builds a
**fixed-size** image: the root partition is sized to the rootfs
contents with no slack, so a freshly flashed card boots ~100% full.
Stock Raspberry Pi OS expands on first boot via `init_resize.sh`, but
that is triggered by an `init=` hook in `cmdline.txt` and is hardcoded
to the stock `PARTUUID` mmcblk layout — this image has no such hook and
roots off `/dev/disk/by-slot/system` (a label-keyed udev symlink), so
`init_resize.sh` neither runs nor applies.

Instead this recipe ships `zbitx-expand-rootfs.service` (oneshot,
ordered before `lightdm`), which calls `/usr/local/sbin/zbitx-expand-rootfs`
to `growpart` the root partition to fill the device and `resize2fs` the
filesystem online, then writes `/var/lib/zbitx/rootfs-expanded` so it
runs only once. It self-skips in containers (`ConditionVirtualization=!container`)
so the CI nspawn boot test is unaffected. Growing the last partition is
safe for the slot layout because the `by-slot` symlinks key on the
filesystem **label** (`ID_FS_LABEL`), which a resize doesn't change.
