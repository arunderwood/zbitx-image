# Bookworm-port patches

The upstream [zbitxv2](https://github.com/afarhan/zbitxv2) codebase
targets Raspbian Buster (see `setup-ap.sh:2`, the drogon.net
wiringPi reference in `install.txt`, and the `ntp`/`ntpstat` apt
deps). This recipe targets Raspberry Pi OS Bookworm (arm64), so several
upstream assumptions have to be patched in the image-build flow.

These patches live in the recipe (in `stage-zbitx`) rather than as
upstream PRs to zbitxv2 so the image work doesn't block on review. They
are candidates to upstream once they're proven on real hardware.

## Active patches

### 1. WiringPi 3.x replaces drogon.net 2.x

- **What**: Install
  [WiringPi/WiringPi](https://github.com/WiringPi/WiringPi) 3.18
  from a downloaded `.deb` instead of the drogon.net package.
- **Why**: drogon.net is offline; the original 2.x line is
  deprecated upstream and has no Bookworm release. WiringPi 3.x is
  "fully verified on Bookworm and Trixie" per its release notes.
- **Where**: `pi-gen.config` pins the URL and SHA256
  (`ZBITX_WIRINGPI_URL` / `ZBITX_WIRINGPI_SHA256`);
  `stage-zbitx/01-zbitx-app/00-run.sh` downloads, verifies, and installs.
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

- **What**: Don't add `ntp` / `ntpstat`. Bookworm ships
  `systemd-timesyncd` by default (present in the pi-gen base).
- **Why**: Debian Bookworm replaced classic `ntp` with `ntpsec` (or
  use timesyncd). `ntpstat` doesn't speak timesyncd.
- **Where**: `stage-zbitx/00-install-packages/00-packages` omits them.
- **Risk**: Low. `ntputil.c` implements NTP directly without
  shelling out to `ntpd`/`ntpstat`, so the packages were never
  load-bearing for the app.

### 3. setup-ap.sh is not executed at build time

- **What**: Upstream `setup-ap.sh:42-51` rewrites
  `/etc/apt/sources.list` to point at `archive.debian.org` — fine
  on EOL Buster, fatal on Bookworm. Rather than patch the script,
  the recipe simply does not run it. The AP stack (hostapd, dnsmasq,
  the `uap0` virtual interface, snd-aloop modprobe, iptables) is laid
  down declaratively via the file overlay.
- **Where**: The static configs live under
  `stage-zbitx/02-zbitx-os/files/rootfs/etc/{hostapd,dnsmasq.d,systemd/system,iptables,modprobe.d,modules-load.d,NetworkManager}`;
  `stage-zbitx/02-zbitx-os/00-run.sh` enables the services.
- **Risk**: Low. The recipe ships `setup-ap.sh` to the flashed
  image at `/home/pi/sbitx/setup-ap.sh` for reference, but doing
  nothing means an operator who explicitly runs it on a built
  image will hit the apt-sources rewrite. This is a niche path
  we don't defend against — by the time the script runs, the AP
  is already configured.

### 4. WiFi: hybrid NetworkManager + hostapd AP

- **What**: Keep stock NetworkManager managing the `wlan0` *client*
  link, and run the zbitx access point as hostapd + dnsmasq on a
  virtual `uap0` interface that NetworkManager is told to leave
  unmanaged. `dhcpcd` is not used (NM owns `wlan0`; `uap0.service`
  assigns the AP's static IP itself).
- **Why**: stock Raspberry Pi OS Bookworm uses NetworkManager, and
  Raspberry Pi Imager provisions client WiFi by writing an NM
  connection — so keeping NM makes Imager WiFi provisioning work out
  of the box. (The previous rpi-image-gen recipe disabled NM in favour
  of `dhcpcd`, which broke that.)
- **Where**: `stage-zbitx/02-zbitx-os/files/rootfs/etc/NetworkManager/conf.d/99-zbitx-uap0-unmanaged.conf`
  marks `uap0` unmanaged; the AP configs are in the same overlay tree;
  `uap0.service` builds the interface.
- **Caveat (hardware, not recipe)**: concurrent AP + client on the
  Pi's single onboard radio is an officially **unsupported** mode
  ("educational use only" per RaspAP; not advertised by the Pi
  Foundation). Both interfaces are forced onto the same channel
  (`zbitx-ap-channel` runs as an `ExecStartPre` on `hostapd.service` and
  pins the AP to the live `wlan0` channel; `channel=0`/ACS doesn't work
  on brcmfmac), throughput roughly halves, and the link can drop over
  long uptimes
  ([bookworm-feedback#220](https://github.com/raspberrypi/bookworm-feedback/issues/220)).
  A second USB WiFi adapter is the only fully-supported path. The
  hostapd-on-`uap0` approach is kept (rather than a NetworkManager-native
  AP) because even RaspAP's NM-based solution does it this way — the
  concurrency is the fragile part regardless of tooling.

### 5. arm64 validation of historically-armhf code paths

- **What**: This image targets arm64 on the Pi Zero 2 W. Upstream
  zbitxv2 was developed against 32-bit Raspbian Buster (armhf), so
  the GPIO, I2C, audio, and DSP code paths have not previously been
  exercised under 64-bit Linux.
- **Why it's the target**: arm64 is the supported architecture for
  this image. The Pi Zero 2 W's BCM2710A1 is a 64-bit part, and the
  base comes from pi-gen's `bookworm-arm64` branch (that branch
  hardcodes `ARCH=arm64`; the `bookworm` branch is armhf).
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
- **Where**: `stage-zbitx/01-zbitx-app/files/build-sbitx.sh`.
- **Risk**: Low. `ft8_lib`'s own Makefile knows how to rebuild;
  we're just exercising it. The only way this breaks is if upstream
  changes the build system inside `ft8_lib/`.
- **Upstream fix**: Drop `libft8.a` from the upstream repo entirely
  and have the top-level `./build` always rebuild. Committing
  prebuilt static libraries is fragile and breaks any arch other
  than the one the maintainer happened to build on. Candidate to
  upstream once the recipe is proven on real hardware.

## No longer patched — inherited from the pi-gen base

Moving to pi-gen (stock Raspberry Pi OS Desktop + a delta) removed
several workarounds the old rpi-image-gen / Debian-base recipe needed.
These are now provided by upstream stages and are **not** maintained
here:

- **First-boot rootfs expansion** — pi-gen's stage2 enables
  `resize2fs_once` (the stock `init_resize` path), so the card expands
  on first boot. The old custom `zbitx-expand-rootfs.service` +
  `growpart` helper are gone. (The original rpi-image-gen `image-rpios`
  layout built a fixed-size image with no first-boot hook — discovered
  the hard way on the 2026-05-28 boot, which came up ~100% full and
  never reached the GUI.)
- **`iw` / `wireless-regdb`** — present in stock Raspberry Pi OS, so the
  `uap0`/hostapd AP no longer needs them listed explicitly. (The old
  Recommends-off mmdebstrap build pulled in neither, which crash-looped
  hostapd on the 2026-05-28 boot.)
- **Pixel desktop add-ons (the "hollow desktop")** — pi-gen installs
  Recommends, so stage3/stage4 deliver the complete desktop (panel menu,
  theme, applets) with no curated package list.
- **SSH host-key + machine-id regeneration** — stage2 strips the baked
  keys and enables `regenerate_ssh_host_keys`; no custom cleanup hook.
- **`pi` user group membership** — stage2 adds the first user to
  `audio`/`i2c`/`gpio`/`spi`/`video`/`plugdev`/`dialout`/`input`/…; no
  `usermod` loop needed.
- **Desktop autologin** — stage4 runs `raspi-config do_boot_behaviour B4`;
  no custom lightdm drop-in.

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

When the first image is flashed to a real zBitx:

- [ ] Boots to the Bookworm desktop without kernel panic; the rootfs
  expanded on first boot (`df -h /` shows the full card).
- [ ] `aplay -l` lists card 0 (WM8731) and the three `snd-aloop`
  cards (hw:1, hw:2, hw:3).
- [ ] `i2cdetect -y 1` shows the si5351 (or si570) and the OLED.
- [ ] The WiFi AP `zbitx` appears, AND a client WiFi network set in
  Raspberry Pi Imager associates (the hybrid NM + AP model).
- [ ] sbitx GTK UI launches under the X11 session and the spectrum
  display is alive.
- [ ] TX works on at least one band (relay sequencing in
  `tr_switch_v2` operating correctly).
- [ ] Web UI at `http://192.168.4.1/` (NAT-redirected from :80
  to :8080) loads.

Each failure becomes either an additional patch in this document or
an upstream PR to zbitxv2.
