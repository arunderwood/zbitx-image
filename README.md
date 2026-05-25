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
- FFTW3 built from source (double + single precision).
- The zbitxv2 binary, built from a pinned submodule SHA.
- WiFi AP setup (SSID `zbitx`, IP `192.168.4.1`) derived from
  [setup-ap.sh](https://github.com/afarhan/zbitxv2/blob/main/setup-ap.sh).
- iptables NAT redirect port 80 → 8080 for the embedded mongoose
  web UI.
- `snd-aloop` virtual ALSA cards for WSJT-X integration.
- AudioInjector WM8731 dtoverlay + GPIO/I2C/I2S enabled in
  `config.txt`.
- A `sbitx-firstboot.service` one-shot that regenerates SSH host
  keys, wipes build-time FFTW wisdom, and disables itself.

## Repo layout

```
zbitxv2-image/
├── config/
│   └── zbitx-bookworm.yaml         # top-level rpi-image-gen config
├── layer/
│   ├── zbitx-sbitx.yaml            # the custom layer
│   ├── scripts/                    # build-time scripts run inside the chroot
│   │   ├── build-fftw.sh
│   │   ├── build-sbitx.sh
│   │   └── os-config.sh
│   └── files/                      # rootfs file overlays (etc, boot, usr)
├── tests/chroot/                   # in-chroot smoke tests (Phase 1 gate)
├── docs/
│   ├── architecture.md
│   └── bookworm-patches.md
├── rpi-image-gen/                  # submodule, pinned to v2.6.0
├── vendor/sbitx/                   # submodule, pinned zbitxv2 SHA
└── .github/workflows/build.yml     # CI on ubuntu-24.04-arm
```

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
git clone --recurse-submodules <this-repo>
cd zbitxv2-image
sudo bash ./rpi-image-gen/install_deps.sh
sudo ./rpi-image-gen/rpi-image-gen build -S "$PWD" -c zbitx-bookworm.yaml
```

Output: `./work/zbitx-bookworm/zbitx-bookworm.img.zst`.

### Building in CI

Push to a branch and let `.github/workflows/build.yml` build it on a
free arm64 runner. The `.img.zst` and SBOM are uploaded as artifacts.

## Flashing

The image ships **with no default password** — the `pi` user account
is created but locked. This mirrors modern Raspberry Pi OS behavior
(since April 2022 no OS image has shipped with a baked-in default
password).

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/):

1. Pick the downloaded `zbitx-bookworm-arm64-img.zip` artifact (extract
   the `.img.zst` from inside, decompress with `zstd -d`, point Imager
   at the resulting `.img`).
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

## Known limitations

- **Not booted on real hardware yet** — see Status.
- **QEMU `raspi4b` smoke test omitted** from CI; the Pi Zero 2 W and
  the WM8731 codec are not faithfully emulated.
- **arm64 not armhf** — original zbitxv2 was developed against 32-bit
  Raspbian Buster. We're testing whether the GPIO/I2C/audio code paths
  work under 64-bit Bookworm. Real-hardware validation is essential.

## Related repos

- [afarhan/zbitxv2](https://github.com/afarhan/zbitxv2) — the radio
  application itself (vendored as `vendor/sbitx`).
- [raspberrypi/rpi-image-gen](https://github.com/raspberrypi/rpi-image-gen)
  — the image builder (vendored as `rpi-image-gen`).
- [WiringPi/WiringPi](https://github.com/WiringPi/WiringPi) — the
  community-maintained 3.x fork of wiringPi.

## License

MIT, matching the upstream zbitxv2 project.
