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
- **API compatibility (verified 2026-05-26 against WiringPi 3.18
  headers)**: All twelve wiringPi symbols sbitx calls
  (`wiringPiSetup`, `wiringPiISR`, `pinMode`, `pullUpDnControl`,
  `digitalRead`, `digitalWrite`, `delay`, `delayMicroseconds`,
  `millis`, `wiringPiI2CSetup`, `wiringPiI2CReadReg8`,
  `wiringPiI2CWriteReg8`) are present with unchanged signatures
  and the same `INPUT/OUTPUT/HIGH/LOW/PUD_*/INT_EDGE_*` constants.
  No source patches required. `wiringPiSetup()` (legacy wPi pin
  numbering) remains the correct entry point on Pi Zero 2 W arm64.
- **Behavioral nuance**: WiringPi 3.x routes `wiringPiISR` through
  the gpio chardev (libgpiod-style) rather than the now-removed
  sysfs `/sys/class/gpio` — transparent to callers. The one
  behavior diff: 3.18 actually returns errors from `wiringPiISR()`
  where 2.x silently swallowed them. sbitx ignores the return
  value at `sbitx_gtk.c:3828-3831`; if encoder/PTT/dash ISRs
  don't fire on first real-hardware boot, the return value is the
  first thing to check (consider patching to log failures rather
  than silently proceeding).

### 2. Drop `ntp` / `ntpstat`

- **What**: Remove `ntp` and `ntpstat` from the apt package list.
  Bookworm ships `systemd-timesyncd` by default.
- **Why**: Debian Bookworm replaced classic `ntp` with `ntpsec` (or
  use timesyncd). `ntpstat` doesn't speak timesyncd.
- **Where**: `layer/zbitx-sbitx.yaml` doesn't include them.
- **Risk**: Low. `ntputil.c` implements NTP directly without
  shelling out to `ntpd`/`ntpstat`, so the packages were never
  load-bearing for the app.

### 3. setup-ap.sh is not executed at build time

- **What**: Upstream `setup-ap.sh:42-51` rewrites
  `/etc/apt/sources.list` to point at `archive.debian.org` — fine
  on EOL Buster, fatal on Bookworm. Rather than patch the script,
  the recipe simply does not run it. The AP stack (hostapd,
  dnsmasq, dhcpcd, iptables, uap0 virtual interface, snd-aloop
  modprobe) is laid down declaratively via the file overlay in
  `layer/files/`.
- **Where**: The static configs live under
  `layer/files/etc/{hostapd,dnsmasq.d,systemd/system,dhcpcd.conf.d,iptables}`.
- **Risk**: Low. The recipe ships `setup-ap.sh` to the flashed
  image at `/home/pi/sbitx/setup-ap.sh` for reference, but doing
  nothing means an operator who explicitly runs it on a built
  image will hit the apt-sources rewrite. This is a niche path
  we don't defend against — by the time the script runs, the AP
  is already configured.

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

### 5. arm64 validation of historically-armhf code paths

- **What**: This image targets arm64 on the Pi Zero 2 W. Upstream
  zbitxv2 was developed against 32-bit Raspbian Buster (armhf), so
  the GPIO, I2C, audio, and DSP code paths have not previously been
  exercised under 64-bit Linux.
- **Why it's the target**: arm64 is the supported architecture for
  this image. The Pi Zero 2 W's BCM2710A1 is a 64-bit part, modern
  Debian and Pi OS releases prioritise arm64, and rpi-image-gen's
  `rpizero2w` device layer is arm64-native.
- **Risk**: The C source has no architecture-specific assembly and
  no obvious bitness assumptions, but pointer-size or sizeof()
  differences could lurk in code that has only ever run armhf. The
  `ft8_lib/libft8.a` prebuilt static library committed upstream is
  armhf — we rebuild it from source (see section 6) but other
  buried armhf assumptions may surface. Real-hardware validation
  is the only way to know.

### 6. Rebuild `ft8_lib/libft8.a` for arm64

- **What**: Run `make clean && make all && make install` inside
  `ft8_lib/` before invoking the top-level `./build sbitx`.
- **Why**: The upstream repo commits a prebuilt `ft8_lib/libft8.a`
  static library that was compiled on a 32-bit armhf Pi. The arm64
  linker rejects it with `ft8_lib/libft8.a: error adding symbols:
  file in wrong format`. Rebuilding from source produces an
  arm64-native archive that links cleanly.
- **Where**: `layer/scripts/build-sbitx.sh`.
- **Risk**: Low. `ft8_lib`'s own Makefile knows how to rebuild;
  we're just exercising it. The only way this breaks is if upstream
  changes the build system inside `ft8_lib/`.
- **Upstream fix**: Drop `libft8.a` from the upstream repo entirely
  and have the top-level `./build` always rebuild. Committing
  prebuilt static libraries is fragile and breaks any arch other
  than the one the maintainer happened to build on. Candidate to
  upstream once the recipe is proven on real hardware.

### 7. First-boot rootfs expansion

- **What**: Ship `zbitx-expand-rootfs.service` + `/usr/local/sbin/zbitx-expand-rootfs`,
  enabled at boot, which `growpart` the root partition to fill the SD
  card and `resize2fs` the filesystem, then self-disable via
  `/var/lib/zbitx/rootfs-expanded`. Adds `cloud-guest-utils` (for
  `growpart`) to the package list.
- **Why**: `image-rpios` builds a fixed-size image (root partition sized
  to the rootfs, no slack). Unlike stock Raspberry Pi OS there is no
  `init=`/`init_resize.sh` hook, and the by-slot/label root layout
  wouldn't work with it anyway. **Discovered on the first real-hardware
  boot (2026-05-28): the card booted ~100% full, every write hit ENOSPC,
  and the graphical session never came up — lightdm's autologin session
  and greeter both exited immediately failing to write `~/.Xauthority`
  ("No space left on device"), leaving a black screen with a blinking
  cursor.**
- **Where**: `layer/files/etc/systemd/system/zbitx-expand-rootfs.service`,
  `layer/files/usr/local/sbin/zbitx-expand-rootfs`,
  `layer/scripts/os-config.sh` (chmod), `layer/zbitx-sbitx.yaml`
  (package + `systemctl enable`).
- **Risk**: Low. Online growpart+resize2fs of the last MBR partition is
  the standard cloud-image pattern; the service skips containers so CI's
  nspawn boot test is unaffected, and runs before `lightdm` so space is
  available before the GUI starts.
- **Why not rpi-image-gen's `expand-to-fit`?** rpi-image-gen does have an
  `expand-to-fit: true` partition flag, and `simple_dual` even sets it on
  the root partition — but it's a **provisioning-map** property honored
  only by the `rpi-sb-provisioner` / IDP fastboot flow (`bin/idp.sh`
  writes the image to a device and expands then). It does nothing for the
  plain `.img.zst`: `genimage` bakes root at content size, `post-image.sh`
  only embeds the pmap as IDP metadata, and CI ships only the `.img.zst`
  (the IDP archive is deliberately not published). Since users flash the
  `.img` with Raspberry Pi Imager, `expand-to-fit` never fires — hence the
  first-boot service. Switching to the provisioner flow would honor it
  natively but isn't an end-user "flash with Imager" path.

### 8. Install `iw` and `wireless-regdb` explicitly

- **What**: Add `iw` and `wireless-regdb` to the apt package list.
- **Why**: Both ship on stock Raspberry Pi OS but neither is a hard
  dependency of `hostapd`, and this mmdebstrap build installs with
  Recommends off, so nothing pulled them in. **Discovered on the first
  real-hardware boot (2026-05-28): `uap0.service` runs
  `iw dev wlan0 interface add uap0` and failed with "Failed to locate
  executable /sbin/iw", which cascaded into a `hostapd` crash-loop and
  `dnsmasq` failure — the `zbitx` AP never came up. `cfg80211` also
  logged "failed to load regulatory.db".**
- **Where**: `layer/zbitx-sbitx.yaml` package list.
- **Risk**: None. Restores tooling that the AP stack (`uap0.service`,
  `hostapd.conf`) already assumed was present.

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

The in-chroot test `60-overlays-present.sh` catches the dtoverlay
regression at build time. The rest will only surface on first boot.

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
