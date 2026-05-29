# zbitxv2-image

Reproducible, auditable Raspberry Pi SD-card image build for the
[zbitxv2](https://github.com/afarhan/zbitxv2) amateur-radio SDR
transceiver software, targeting the zBitx v2 hardware (Raspberry Pi
Zero 2 W + sBitx radio board).

The recipe uses [rpi-image-gen](https://github.com/raspberrypi/rpi-image-gen)
to layer the zbitxv2 build on top of a Debian Bookworm base, producing
a flashable `.img.zst` plus an SBOM.

## Status

**Phase 1 — first real-hardware boot done (2026-05-28); re-validation
in progress.** The first flash to real zBitx v1 hardware reached
multi-user/SSH but the graphical session never started: the rootfs
shipped 100% full (rpi-image-gen builds a fixed-size image and nothing
expanded it on first boot), so lightdm died writing `~/.Xauthority`
with ENOSPC — a black screen with a blinking cursor. The WiFi AP stack
was also missing `iw`. Both are now fixed (see patches 7–8 in
[docs/bookworm-patches.md](docs/bookworm-patches.md)); a re-flash to
confirm the GUI + AP come up is pending.

## What it builds

- Base: Debian Bookworm + Raspberry Pi apt repo + `raspberrypi-ui-mods`
  (the meta-package that turns RPi OS Lite into RPi OS Desktop).
  Arm64.
- Target hardware: Raspberry Pi Zero 2 W (zBitx v2). The same image
  is expected to work on zBitx v1 hardware via the runtime hardware
  auto-detect at [sbitx.c:1411-1416](https://github.com/afarhan/zbitxv2/blob/main/sbitx.c#L1411).
- Apt packages from [install.txt](https://github.com/afarhan/zbitxv2/blob/main/install.txt)
  minus deprecated `ntp`/`ntpstat`.
- WiringPi 3.x (Gordon's unofficial fork — drogon.net is offline).
- FFTW3 double + single precision from Bookworm packages
  (`libfftw3-dev` + `libfftw3-single3`).
- The zbitxv2 binary, built from a pinned submodule SHA.
- WiFi AP setup (SSID `zbitx`, IP `192.168.4.1`) derived from
  [setup-ap.sh](https://github.com/afarhan/zbitxv2/blob/main/setup-ap.sh).
- iptables NAT redirect port 80 → 8080 for the embedded mongoose
  web UI.
- `snd-aloop` virtual ALSA cards for WSJT-X integration.
- AudioInjector WM8731 dtoverlay + GPIO/I2C/I2S enabled in
  `config.txt`.
- SSH host keys + machine-id + bundled FFTW wisdom deleted at
  build time so first boot regenerates them naturally via their own
  services (no custom script needed for these).
- First-boot rootfs expansion: `zbitx-expand-rootfs.service` grows the
  root partition + ext4 filesystem to fill the SD card, since
  rpi-image-gen's `image-rpios` builds a fixed-size image.

## Repo layout

```
zbitxv2-image/
├── config/
│   └── zbitx-bookworm.yaml         # top-level rpi-image-gen config
├── layer/
│   ├── zbitx-sbitx.yaml            # the custom layer
│   ├── scripts/                    # build-time scripts run inside the chroot
│   │   ├── build-sbitx.sh
│   │   └── os-config.sh
│   └── files/                      # rootfs file overlays (etc, boot, usr)
├── tests/chroot/                   # in-chroot smoke tests (build-time gate)
├── docs/
│   ├── architecture.md             # recipe layout + validation tiers
│   └── bookworm-patches.md         # divergences from upstream zbitxv2
├── vendor/sbitx/                   # submodule, pinned zbitxv2 SHA
└── .github/workflows/build.yml     # CI on ubuntu-24.04-arm + nspawn boot test
```

rpi-image-gen itself is not vendored. CI clones it at a pinned tag
(`RPI_IMAGE_GEN_REF` in [.github/workflows/build.yml](.github/workflows/build.yml));
local builders clone it once and point it at this repo with `-S` (see
"Building locally" below).

## Building

### Prerequisites

rpi-image-gen requires a native arm64 Linux host running Debian Bookworm
or Trixie. Practical options:

- A Raspberry Pi 4 or 5 running Bookworm 64-bit (officially supported).
- A free Oracle Ampere or other arm64 cloud VM with Bookworm.
- GitHub Actions `ubuntu-24.04-arm` runner (what this repo's CI uses).
- WSL2 with Bookworm — possible but not formally supported by upstream;
  expect rough edges.

### Building locally

```bash
# 1. Clone this recipe (with the zbitxv2 submodule).
git clone --recurse-submodules <this-repo>
cd zbitxv2-image

# 2. Clone rpi-image-gen at the same pinned tag CI uses.
#    Reuse the same clone across multiple recipe repos if you like.
git clone --depth=1 --branch v2.6.0 \
    https://github.com/raspberrypi/rpi-image-gen.git ../rpi-image-gen

# 3. One-time: install rpi-image-gen's host deps.
sudo bash ../rpi-image-gen/install_deps.sh

# 4. Build. `-S "$PWD"` tells rpi-image-gen to look in *this* repo for
#    config/ and layer/; nothing in the tool's clone is modified.
sudo ../rpi-image-gen/rpi-image-gen build -S "$PWD" -c zbitx-bookworm.yaml
```

Output: `./work/deploy-<version>/zbitx-bookworm.img.zst`, where
`<version>` is `git describe --tags --always --dirty` (or today's
date if not a git checkout).

The pinned rpi-image-gen version lives in
`.github/workflows/build.yml` (`RPI_IMAGE_GEN_REF`); bumping CI and
local builds is a single env-var change.

### Building in CI

Push to a branch and let `.github/workflows/build.yml` build it on a
free arm64 runner. After the build, the workflow boots the rootfs in
systemd-nspawn and checks that PID 1 reaches `multi-user.target`. The
`.img.zst`, SBOM, build log, and nspawn boot log are uploaded as
artifacts.

## Flashing

The image ships **with no default password** — the `pi` user account
is created but locked. This mirrors modern Raspberry Pi OS behavior
(since April 2022 no OS image has shipped with a baked-in default
password).

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
(v1.8.0 or later — it handles `.img.zst` natively, no manual
decompression needed):

1. Unzip the downloaded `zbitx-bookworm-arm64-img.zip` artifact and
   point Imager at the `zbitx-bookworm.img.zst` inside ("Use custom"
   in the OS picker).
2. Click the gear icon (or "Edit settings…") **before** writing:
   - **Set username** to `pi` (this is required — zbitxv2 hardcodes
     `/home/pi/sbitx/` paths).
   - Set a password of your choice (or upload an SSH key).
   - Optionally pre-configure WiFi client credentials, locale, etc.
3. Write to the SD card.

Imager writes a `firstrun.sh` + `userconf.txt` to the boot partition;
the kernel runs them on first boot to set the password, create the
SSH directories, and apply your WiFi settings.

After boot:

- lightdm auto-logs into the `pi` user (the standard
  `raspi-config nonint do_boot_behaviour B4` "Desktop with autologin"
  mode). The Pixel/Wayfire desktop session starts;
  `/etc/xdg/autostart/sBitx.desktop` fires the sbitx GTK UI.
- The WiFi AP `zbitx` (passphrase `zbitx12345`) comes up on
  `192.168.4.1`. (Configurable via `/etc/hostapd/hostapd.conf`.)
- The mongoose web UI is at `http://192.168.4.1/` (iptables redirects
  port 80 → 8080 internally).
- SSH listens on port 22; first boot regenerated unique host keys.

### Hardware variant

The image ships configured for **zBitx v1 hardware** (the project
maintainer's hardware): `hw_settings.ini` has `hw=4`, `bfo_freq=40035000`,
and the v1 per-band TX power scaling table.

The runtime auto-detect at [sbitx.c:1411-1416](https://github.com/afarhan/zbitxv2/blob/main/sbitx.c#L1411)
only chooses between older sBitx kit boards (DE vs V2-kit) by probing
I2C address 0x8. It cannot select `SBITX_V4` — which is what both zBitx
v1 and zBitx v2 hardware actually need. So the right config is selected
at build time, not detected at runtime.

**For zBitx v2 hardware**, swap to the v2 settings after first boot:

```bash
ssh pi@192.168.4.1    # or your home-WiFi DHCP address
cp /home/pi/sbitx/data/hw_settings.zbitx_v2 /home/pi/sbitx/data/hw_settings.ini
sudo systemctl reboot
```

Both variants use the same `hw=4` code path; the swap changes BFO
calibration (40035000 → 40048000 Hz), adds `center_bin=600`, and
replaces the per-band TX power scaling table with v2-tuned values.

### For zBitx v1 users upgrading from the original sbitx software

The SD card is only half the upgrade. The front-panel Pico's firmware
also has to be reflashed — the new sbitx (`zbitxv2`) talks to the
front panel over WiFi rather than I2C, and the old firmware doesn't
know how. Without this step, the screen comes up white and touch /
VFO knob don't respond. After first boot:

1. Power off the radio. Connect a USB cable to the **CAT** port (not
   the port marked USB).
2. Hold the **tuning knob pushed down** while powering on. The screen
   lights dim white — the front panel is in UF2 upload mode and
   appears as a USB drive on your computer.
3. Copy `zbitx_front_panel_v2.ino.uf2` to that drive. The image ships
   the UF2 at `/home/pi/sbitx/zbitx_front_panel_v2.ino.uf2` — grab it
   via `scp`, or download fresh from
   [upstream](https://github.com/afarhan/zbitxv2/blob/main/zbitx_front_panel_v2.ino.uf2).
   The front panel reboots and associates over WiFi.
4. If touch is misaligned after the upgrade: power off, then power on
   with the **stylus held on the screen**. Red arrows appear in the
   four corners — tap each, then restart.

Keep the radio on AC during the firmware flash; low battery has been
reported to cause failed UF2 copies on the BITX20 list.

## Security model

This image matches upstream zbitxv2's network posture: **no host
firewall**. `iptables`'s `*filter` table is left at default-ACCEPT
policy and the only rules shipped are the NAT redirect for the web UI
(port 80 → 8080). The WPA2 passphrase on the `zbitx` AP is the
network-level security boundary; the listening services on the device
(SSH on 22, mongoose web UI on 8080, telnet CAT server on 8081) are
reachable from any client associated to the AP.

Operationally, this means:

- **The default AP passphrase is `zbitx12345` and is publicly
  documented.** Anyone deploying the image outside a controlled RF
  environment should change it in `/etc/hostapd/hostapd.conf` before
  putting the radio on the air.
- **The image has no default password** for the `pi` user — set one
  via Raspberry Pi Imager's "Edit settings…" pane before flashing
  (see Flashing above).
- **TODO**: an optional hardened-firewall layer that defaults INPUT
  to DROP and allows only the listening services + DHCP/DNS on
  `uap0` is a candidate for a future version. Not in v0.1.

## Known limitations

- **Real-hardware validation in progress** — first boot (2026-05-28)
  surfaced two first-boot defects (rootfs not expanded; `iw` missing),
  now fixed; a re-flash to confirm the GUI + AP is pending. See Status.
- **No QEMU boot test in CI.** QEMU's `raspi3b`/`raspi4b` machines
  don't emulate the Pi firmware path well enough to reliably boot a
  Pi OS image to a login prompt, and the WM8731 codec / GPIO / I2C
  aren't modeled at all. The CI Tier-1 systemd-nspawn boot test
  catches userspace bootup regressions; everything kernel- or
  hardware-dependent is real-hardware-only.
- **arm64 validation of historically-armhf code paths** — this image
  targets arm64 on the Pi Zero 2 W. Upstream zbitxv2 was developed
  against 32-bit Raspbian Buster, so the GPIO/I2C/audio code paths
  have not been exercised under 64-bit Linux. Real-hardware validation
  is essential — see [docs/bookworm-patches.md](docs/bookworm-patches.md).

## Related repos

- [afarhan/zbitxv2](https://github.com/afarhan/zbitxv2) — the radio
  application itself (vendored as `vendor/sbitx`).
- [raspberrypi/rpi-image-gen](https://github.com/raspberrypi/rpi-image-gen)
  — the image builder. Cloned at the pinned `RPI_IMAGE_GEN_REF` tag
  by CI and local builds; not vendored.
- [WiringPi/WiringPi](https://github.com/WiringPi/WiringPi) — the
  community-maintained 3.x fork of wiringPi.

## License

MIT, matching the upstream zbitxv2 project.
