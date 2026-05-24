# Bookworm-port patches

The upstream [zbitxv2](https://github.com/afarhan/zbitxv2) codebase
targets Raspbian Buster (see `setup-ap.sh:2`, the drogon.net
wiringPi reference in `install.txt`, and the `ntp`/`ntpstat` apt
deps). This recipe targets Bookworm, so several upstream assumptions
have to be patched in the image-build flow.

These patches live in the recipe rather than as upstream PRs to
zbitxv2 so the image work doesn't block on review. They are
candidates to upstream once they're proven on real hardware.

## Active patches

### 1. WiringPi 3.x replaces drogon.net 2.x

- **What**: Install
  [WiringPi/WiringPi](https://github.com/WiringPi/WiringPi) 3.18
  from a downloaded `.deb` instead of the drogon.net package.
- **Why**: drogon.net is offline; the original 2.x line is
  deprecated upstream and has no Bookworm release. WiringPi 3.x is
  "fully verified on Bookworm and Trixie" per its release notes.
- **Where**: `layer/zbitx-sbitx.yaml` declares the URL and SHA256
  as variables; the first customize-hook downloads, verifies, and
  installs.
- **Risk**: Unknown whether WiringPi 3.x's API matches 2.x for the
  symbols zbitxv2 uses. Validate by reviewing
  `grep -rn 'wiringPiSetup\|digitalRead\|digitalWrite\|pullUpDnControl\|wiringPiI2C' *.c`
  in the zbitxv2 source against the 3.x API. If signatures diverge,
  patch the source in `build-sbitx.sh`.

### 2. Drop `ntp` / `ntpstat`

- **What**: Remove `ntp` and `ntpstat` from the apt package list.
  Bookworm ships `systemd-timesyncd` by default.
- **Why**: Debian Bookworm replaced classic `ntp` with `ntpsec` (or
  use timesyncd). `ntpstat` doesn't speak timesyncd.
- **Where**: `layer/zbitx-sbitx.yaml` doesn't include them.
- **Risk**: Low. `ntputil.c` implements NTP directly without
  shelling out to `ntpd`/`ntpstat`, so the packages were never
  load-bearing for the app.

### 3. Skip the `archive.debian.org` source rewrite in setup-ap.sh

- **What**: `setup-ap.sh:42-51` actively rewrites
  `/etc/apt/sources.list` to point at `archive.debian.org`. On
  Bookworm (which is current, not archived), this would break apt.
- **Where**: `layer/scripts/build-sbitx.sh` patches the script with
  a sed before invoking the build.
- **Risk**: Low. The patch is anchored on the comment "Patch
  sources.list" and the closing `fi`; if the upstream script
  changes structure, the patch may silently no-op (in which case
  it falls back to "the script runs, fails on Bookworm sources,
  recipe surfaces the error").

### 4. dhcpcd over NetworkManager

- **What**: Install `dhcpcd5` and disable NetworkManager. The
  upstream `setup-ap.sh` edits `/etc/dhcpcd.conf`; that file
  doesn't exist when NetworkManager is the default.
- **Where**: `layer/zbitx-sbitx.yaml` package list and
  `os-config.sh`'s `systemctl disable NetworkManager`.
- **Risk**: Loses NetworkManager's nicer WiFi-client UX. If the
  user wants to associate the Pi to a home WiFi while keeping the
  AP up, they'll need to configure wpa_supplicant or
  `/etc/dhcpcd.conf` directly.
- **Future**: Rewrite `setup-ap.sh`'s network bits as NM connection
  profiles. Out of scope for v0.1.

### 5. arm64, not armhf

- **What**: Build a 64-bit arm image. zbitxv2's original Buster
  image was armhf.
- **Why**: rpi-image-gen's `rpizero2w` device layer is arm64-only.
  Producing an armhf image with rpi-image-gen would require a
  custom device layer (out of scope for v0.1).
- **Risk**: Higher than the other patches. zbitxv2's GPIO, I2C,
  and audio code paths have only been validated under 32-bit
  Linux. The C source has no architecture-specific assembly and
  no obvious bitness assumptions, but pointer-size or sizeof()
  differences could lurk. Real-hardware validation is the only
  way to know.

## Unknown unknowns

There may be additional Bookworm regressions that only surface when
running on real hardware:

- ALSA mixer-element names may differ under PipeWire-compat.
- GPIO sysfs has been deprecated in favor of `/dev/gpiochip*` and
  `libgpiod`; WiringPi 3.x should abstract this but specific calls
  may behave differently.
- raspi-firmware overlay parameters may have changed.
- The `audioinjector-wm8731-audio.dtbo` overlay may be in a
  different package or path.

The Phase 1 in-chroot test `60-overlays-present.sh` catches the
dtoverlay regression at build time. The rest will only surface on
first boot.

## Validation checklist (real hardware)

When the first image is flashed to a real zBitx v2:

- [ ] Boots to the Bookworm login prompt without kernel panic.
- [ ] `aplay -l` lists card 0 (WM8731) and the three `snd-aloop`
  cards (hw:1, hw:2, hw:3).
- [ ] `i2cdetect -y 1` shows the si5351 (or si570) and the OLED.
- [ ] The WiFi AP `zbitx` appears.
- [ ] sbitx GTK UI launches and the spectrum display is alive.
- [ ] TX works on at least one band (relay sequencing in
  `tr_switch_v2` operating correctly).
- [ ] Web UI at `http://192.168.4.1/` (NAT-redirected from :80
  to :8080) loads.

Each failure becomes either an additional patch in this document or
an upstream PR to zbitxv2.
