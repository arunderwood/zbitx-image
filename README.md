# zbitxv2-image

Reproducible, auditable Raspberry Pi SD-card image build for the
[zbitxv2](https://github.com/afarhan/zbitxv2) amateur-radio SDR
transceiver software, targeting the zBitx v2 hardware (Raspberry Pi
Zero 2 W + sBitx radio board).

The recipe uses [rpi-image-gen](https://github.com/raspberrypi/rpi-image-gen)
to layer the zbitxv2 build on top of a Debian Bookworm base, producing
a flashable `.img.zst` plus an SBOM.

## Status

**Phase 1 scaffolding — not yet validated end-to-end.** The recipe
encodes what we believe is needed to build zbitxv2 on Bookworm but has
not been booted on real zBitx hardware. See
[docs/bookworm-patches.md](docs/bookworm-patches.md) for the list of
upstream-divergent patches and what could still break.

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
  build time so first boot regenerates them naturally (no custom
  firstboot script needed).

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
├── tests/chroot/                   # in-chroot smoke tests (Phase 1 gate)
├── docs/
│   ├── architecture.md
│   └── bookworm-patches.md
├── vendor/sbitx/                   # submodule, pinned zbitxv2 SHA
└── .github/workflows/build.yml     # CI on ubuntu-24.04-arm
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
free arm64 runner. The `.img.zst` and SBOM are uploaded as artifacts.

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
- For zBitx v1 hardware, edit `/home/pi/sbitx/data/hw_settings.ini`
  and add `hw=4` if the runtime auto-detect picks the wrong path.

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

- **Not booted on real hardware yet** — see Status.
- **QEMU `raspi4b` smoke test omitted** from CI; the Pi Zero 2 W and
  the WM8731 codec are not faithfully emulated.
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
