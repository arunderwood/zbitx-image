# zbitxv2-image

Reproducible, auditable Raspberry Pi SD-card image build for the
[zbitxv2](https://github.com/afarhan/zbitxv2) amateur-radio SDR
transceiver software, targeting the zBitx v2 hardware (Raspberry Pi
Zero 2 W + sBitx radio board).

The recipe uses [pi-gen](https://github.com/RPi-Distro/pi-gen) — the
official Raspberry Pi OS build system — to add a single `stage-zbitx`
on top of the stock Raspberry Pi OS Desktop (Bookworm, arm64) stages,
producing a flashable `.img.xz` plus an SBOM.

## Status

**Migrated to pi-gen (2026-05).** The build previously assembled a
Debian Bookworm base with `rpi-image-gen` and hand-re-derived the
Raspberry Pi OS niceties (WiFi packages, first-boot rootfs expansion,
the Pixel desktop add-ons, RPi Imager user/WiFi provisioning). That
approach meant continually "reinventing Raspbian." The recipe now
starts from the *actual* Raspberry Pi OS via pi-gen and contributes
only the zbitx delta (`stage-zbitx`); everything generic-Raspbian is
inherited from upstream stages. The legacy rpi-image-gen recipe has been
removed. Real-hardware re-validation on this new base is pending — see
Known limitations.

## What it builds

- Base: stock **Raspberry Pi OS Desktop** (Bookworm, arm64), built by
  pi-gen stages 0–4 — the same pipeline that produces official images.
  WiFi, firmware, `raspi-config`, the full Pixel desktop, RPi Imager
  firstrun/userconf provisioning, and first-boot rootfs expansion all
  come from these stages, not from this repo.
- Target hardware: Raspberry Pi Zero 2 W (zBitx v2). The same image
  is expected to work on zBitx v1 hardware via the runtime hardware
  auto-detect at [sbitx.c:1411-1416](https://github.com/afarhan/zbitxv2/blob/main/sbitx.c#L1411).
- Apt packages from [install.txt](https://github.com/afarhan/zbitxv2/blob/main/install.txt)
  minus deprecated `ntp`/`ntpstat`.
- WiringPi 3.x (Gordon's unofficial fork — drogon.net is offline).
- FFTW3 double + single precision from Bookworm packages
  (`libfftw3-dev` + `libfftw3-single3`).
- The zbitxv2 binary, built from a pinned submodule SHA into
  `/home/pi/sbitx`.
- WiFi: a **hybrid** model. NetworkManager (stock) keeps `wlan0` as the
  client, so RPi Imager WiFi provisioning works out of the box; the
  `zbitx` AP (SSID `zbitx`, IP `192.168.4.1`) runs as hostapd + dnsmasq
  on a virtual `uap0` interface that NetworkManager is told to ignore.
  Derived from [setup-ap.sh](https://github.com/afarhan/zbitxv2/blob/main/setup-ap.sh).
  (Concurrent AP+client on the Pi's single radio is an unsupported,
  same-channel mode — see [docs/architecture.md](docs/architecture.md).)
- iptables NAT redirect port 80 → 8080 for the embedded mongoose
  web UI.
- `snd-aloop` virtual ALSA cards for WSJT-X integration.
- AudioInjector WM8731 dtoverlay + GPIO/I2C/I2S enabled in
  `config.txt`; the desktop audio stack (pipewire/pulseaudio) masked so
  it can't grab the codec.

## Repo layout

```
zbitxv2-image/
├── pi-gen.config                   # top-level pi-gen config (image identity, user, locale)
├── stage-zbitx/                    # the one stage we own (the zbitx delta)
│   ├── prerun.sh                   #   copy the Desktop rootfs forward
│   ├── EXPORT_IMAGE                #   this stage exports the final image
│   ├── 00-install-packages/        #   apt packages (build toolchain, AP stack)
│   ├── 01-zbitx-app/               #   WiringPi + sBitx source build
│   ├── 02-zbitx-os/                #   overlays, config.txt, audio masking, AP, X11
│   └── 03-zbitx-tests/             #   in-chroot smoke tests (build-time gate)
├── scripts/pi-gen-build.sh         # build wrapper (injects stage + suppresses extra images)
├── docs/
│   ├── architecture.md             # recipe layout + validation tiers
│   └── bookworm-patches.md         # divergences from upstream zbitxv2
├── vendor/pi-gen/                  # submodule, pinned (bookworm-arm64 branch)
├── vendor/sbitx/                   # submodule, pinned zbitxv2 SHA
└── .github/workflows/build.yml     # CI on ubuntu-24.04-arm + nspawn boot test
```

pi-gen is a pinned **submodule** (`vendor/pi-gen`). `stage-zbitx` and
`pi-gen.config` live outside it; the build wrapper injects them so the
submodule tree stays pristine. Bump the pin with an explicit
`git -C vendor/pi-gen pull` + commit (Renovate tracks it).

## Building

### Prerequisites

pi-gen builds an arm64 image. On a **native arm64** Linux host (a Pi, an
arm64 cloud VM, or the CI `ubuntu-24.04-arm` runner) no emulation is
needed. On an **x86_64** host (e.g. WSL2) install `qemu-user-static` +
`binfmt-support` first so the arm64 chroot can run. The build runs as
root and needs tens of GB of scratch space (pi-gen keeps a full rootfs
copy per stage).

### Building locally

```bash
# 1. Clone this recipe with submodules (pi-gen tooling + zbitxv2 source).
git clone --recurse-submodules <this-repo>
cd zbitxv2-image

# 2. Build. The wrapper inits submodules, injects stage-zbitx, suppresses
#    the stock -lite/Desktop image exports, and runs pi-gen as root.
./scripts/pi-gen-build.sh
#    Force a clean rebuild (discard cached stage rootfs):
#    CLEAN=1 ./scripts/pi-gen-build.sh
```

Output: `vendor/pi-gen/deploy/image_<date>-zbitx-bookworm.img.xz` plus
(if `syft` is on PATH) an xz-compressed SPDX `.sbom`; a `.info` package
manifest lands under `vendor/pi-gen/work/*/export-image/`.

The pinned pi-gen version is the `vendor/pi-gen` submodule commit; bump
it deliberately and review the diff.

### Building in CI

Push to a branch and let `.github/workflows/build.yml` build it on a
free arm64 runner. After the build, the workflow boots the final
(`stage-zbitx`) rootfs in systemd-nspawn and checks that PID 1 reaches
`multi-user.target`. The `.img.xz`, SBOM/info, build log, and nspawn
boot log are uploaded as artifacts.

## Flashing

The image ships **with no default password** — the `pi` user account
is created but locked. This mirrors modern Raspberry Pi OS behavior
(since April 2022 no OS image has shipped with a baked-in default
password).

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
(it handles `.img.xz` natively, no manual decompression needed):

1. Unzip the downloaded `zbitx-bookworm-arm64-img` artifact and point
   Imager at the `*-zbitx-bookworm.img.xz` inside ("Use custom" in the
   OS picker).
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
  mode, set by the stock desktop stage). The Pixel session starts in
  **X11/openbox** (stage-zbitx pins `do_wayland W1` so the GTK3 sbitx
  app launches via `/etc/xdg/autostart/sBitx.desktop`).
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

- **Real-hardware validation pending on the pi-gen base.** The earlier
  rpi-image-gen build booted to multi-user on real zBitx v1 hardware,
  but the move to pi-gen rebuilds the whole base (Raspberry Pi OS
  Desktop) and the WiFi model (NetworkManager client + hostapd `uap0`
  AP). A flash to confirm the GUI, the AP, and Imager WiFi provisioning
  is required before this is trusted. See Status.
- **Concurrent AP + client is an unsupported Pi mode.** Both run on the
  single onboard radio, forced to the same channel; throughput roughly
  halves and the link can drop over long uptimes. This is inherent to
  the hardware, not the recipe — a second USB WiFi adapter is the only
  fully-supported path. See [docs/architecture.md](docs/architecture.md).
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
- [RPi-Distro/pi-gen](https://github.com/RPi-Distro/pi-gen) — the
  official Raspberry Pi OS build system. Pinned as the `vendor/pi-gen`
  submodule (bookworm-arm64 branch).
- [WiringPi/WiringPi](https://github.com/WiringPi/WiringPi) — the
  community-maintained 3.x fork of wiringPi.

## License

MIT, matching the upstream zbitxv2 project.
