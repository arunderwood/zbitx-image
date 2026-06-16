# Architecture

How the recipe is organized and what each piece does.

## Approach: Raspberry Pi OS + a delta, not Debian + re-derivation

This image is built with [pi-gen](https://github.com/RPi-Distro/pi-gen),
the official Raspberry Pi OS build system. pi-gen produces Raspberry Pi
OS by running an ordered list of **stages**; this recipe appends one
stage of its own — `stage-zbitx` — after the stock Desktop stages.

The point of this design is to **stop re-deriving Raspbian**. Everything
generic to Raspberry Pi OS — the WiFi stack and firmware, `raspi-config`,
the full Pixel desktop (with its add-ons), Raspberry Pi Imager
firstrun/userconf provisioning, first-boot rootfs expansion, SSH
host-key and machine-id regeneration — is produced by the upstream
stages and is *not* maintained here. This repo owns only the zbitx
delta.

(The previous incarnation used `rpi-image-gen` to assemble a bare Debian
Bookworm base and then hand-listed every Raspberry Pi OS package and
behavior that a from-scratch Debian build lacks. That is the work this
migration eliminates.)

### pi-gen stage model (the parts we rely on)

- A **stage** is a directory of ordered **sub-stage** directories. Each
  sub-stage may contain, run in this order by prefix: `NN-debconf`
  (debconf preseeds), `NN-packages-nr` / `NN-packages` (apt installs,
  no-recommends / with-recommends), `NN-patches` (quilt), `NN-run.sh`
  (runs on the host with `${ROOTFS_DIR}` set), and `NN-run-chroot.sh`
  (piped into the chroot). A stage's `prerun.sh` runs first (we use it
  to `copy_previous` the prior rootfs); an `EXPORT_IMAGE` file marks the
  stage that emits a deployable image.
- pi-gen installs **Recommends by default**, so the Pixel desktop comes
  up complete with no curated add-on lists.
- `on_chroot` (a helper exported by pi-gen) runs commands inside the
  rootfs; our host-side `*-run.sh` scripts use it for the in-chroot
  steps (compiling sbitx, enabling services).

Stages run: stock **stage0–stage2** (Lite) → **stage3–stage4**
(Desktop) → **stage-zbitx**. stage5 (the "full" image with LibreOffice
etc.) is excluded.

## This repo's structure

### `pi-gen.config`

The top-level pi-gen config (sourced via `build.sh -c`). Sets the image
identity (`IMG_NAME=zbitx-bookworm`), the first user, locale/keyboard/
timezone/WiFi-country, the deploy format (`xz`), the `STAGE_LIST`, and
the zbitx delta variables (`ZBITX_SRCDIR`, the WiringPi URL/SHA). It is
named `pi-gen.config` (not pi-gen's default `config`) and passed
explicitly with `build.sh -c`, since the wrapper drives the build from
inside the submodule rather than from the repo root.

Two choices here are load-bearing:

- **`FIRST_USER_NAME=pi`, locked, with the piwiz wizard removed.** sbitx
  hardcodes `/home/pi/sbitx` paths, so the user must stay `pi`. pi-gen
  creates `pi` as a *locked* account (`adduser --disabled-password`); we
  deliberately ship no `FIRST_USER_PASS`, so we can't use
  `DISABLE_FIRST_BOOT_USER_RENAME=1` (pi-gen aborts the build unless a
  password is baked — `build.sh:287`). Instead `stage-zbitx` deletes
  `/etc/xdg/autostart/piwiz.desktop` (what the `DISABLE=1` path does
  internally), so no first-boot wizard can rename `pi`. Desktop autologin
  (stage4's `do_boot_behaviour B4`) reaches the GUI without a password,
  `pi` sudoes passwordless (pi-gen's `sudoers.d/010_pi-nopasswd`), and
  operators set a password / WiFi / SSH key via Raspberry Pi Imager's
  `firstrun.sh` (which provisions independently of the rename path).
- **`DEPLOY_COMPRESSION=xz`.** The stock Raspberry Pi OS distribution
  format, ingested natively by Imager. (This pinned pi-gen has no zstd.)

### `stage-zbitx/`

The one stage we own.

- `00-install-packages/` — the zbitx build toolchain and runtime deps,
  plus the AP stack (`hostapd`, `dnsmasq`, `iptables`,
  `iptables-persistent`). A `00-debconf` preseeds `iptables-persistent`
  to not prompt. Nothing stock Raspberry Pi OS already ships is listed.
- `01-zbitx-app/` — downloads + installs WiringPi 3.x, copies the
  vendored sbitx source into `/home/pi/sbitx`, and runs `build-sbitx.sh`
  in the chroot (see below).
- `02-zbitx-os/` — lays down the file overlays (`files/rootfs/…`),
  appends the zbitx `config.txt` block, masks the desktop audio stack,
  pins the X11 session, and enables the AP services. See "WiFi" and
  "Audio" below.
- `03-zbitx-tests/` — copies `files/*.sh` into the chroot and runs them
  as the build-time gate; any non-zero test fails the build.
- `prerun.sh` / `EXPORT_IMAGE` — standard pi-gen stage plumbing;
  `EXPORT_IMAGE` makes this the image-emitting stage.

`build-sbitx.sh` (in `01-zbitx-app/files/`) runs inside the chroot:
rebuilds `ft8_lib` for arm64, runs `./build sbitx`, initializes the
SQLite logbook, seeds `hw_settings.ini` with `hw=4` (the zbitx hardware
auto-detect is wrong for all zbitx boards — it must be seeded), patches
the upstream 40m `f_stop` typo, and deletes the bundled FFTW wisdom so
it regenerates per-CPU on first run.

### `scripts/pi-gen-build.sh`

The build wrapper. `stage-zbitx` and `pi-gen.config` live *outside* the
pinned pi-gen submodule so the submodule tree stays pristine; the
wrapper wires them in at build time:

- exports `ZBITX_ROOT` so `pi-gen.config`'s `STAGE_LIST` can point at the
  external `stage-zbitx`;
- drops a `SKIP_IMAGES` marker in `stage2` and `stage4` so pi-gen does
  **not** also export the stock `-lite` and Desktop images (only
  `stage-zbitx` emits one);
- runs pi-gen's `build.sh` as root with our config.

### WiFi: hybrid NetworkManager + hostapd AP

Stock Raspberry Pi OS Bookworm uses **NetworkManager**. The recipe keeps
it for the `wlan0` *client* connection — which is exactly what Raspberry
Pi Imager's "Edit settings" provisions — and runs the zbitx **access
point** as `hostapd` + `dnsmasq` on a virtual `uap0` interface created by
`uap0.service`. `99-zbitx-uap0-unmanaged.conf` tells NetworkManager to
leave `uap0` alone so it doesn't race hostapd. `dhcpcd` is not used
(NM owns `wlan0`; `uap0.service` assigns the AP's static IP itself).

Because AP+STA shares one channel, the AP must track `wlan0`.
`zbitx-ap-channel` (a pure renderer) writes `wlan0`'s current channel
into `hostapd.conf`; `zbitx-ap-reconcile` wraps it and restarts hostapd
only if the channel actually moved. Three triggers keep the AP aligned:

1. **`ExecStartPre` on `hostapd.service`** runs `zbitx-ap-channel` at AP
   start (covers a hostapd restart while `wlan0` is already up).
2. **NM dispatcher `90-zbitx-ap-follow-channel`** runs `zbitx-ap-reconcile`
   when `wlan0` (re)associates — at boot `wlan0` usually associates
   *after* hostapd has started, and the STA can reconnect on a new
   channel.
3. **`zbitx-ap-follow-channel.timer`** runs `zbitx-ap-reconcile` every
   minute as a safety net for *seamless* upstream channel switches (CSA):
   the firmware drags the AP onto `wlan0`'s new channel, but `wlan0`
   stays associated so NM fires no dispatcher event — without the timer
   hostapd would keep beaconing the old channel and clients would drop.

`channel=0` (ACS) is **not** used: brcmfmac has no survey-dump support,
so ACS fails to bring up the BSS. The AP is 2.4 GHz (`hw_mode=g`); a
5 GHz STA channel can't be followed and is ignored (the Pi's single
radio can't straddle bands anyway).

Why this split rather than a pure-NetworkManager AP: **concurrent AP+STA
on the Pi's single onboard radio is an officially unsupported mode**
("educational use only" per RaspAP; not advertised by the Pi
Foundation). It forces both interfaces onto the same channel
(`zbitx-ap-channel`, an `ExecStartPre` on `hostapd.service`, pins the AP
to the live `wlan0` channel — `channel=0`/ACS is unsupported on
brcmfmac), roughly halves throughput, and has known long-uptime drop bugs
([bookworm-feedback#220](https://github.com/raspberrypi/bookworm-feedback/issues/220)).
Since the concurrency is the fragile part *regardless of tooling*, and
even RaspAP's NetworkManager-based solution runs the AP via hostapd on a
virtual `uap0` interface, the recipe keeps the proven hostapd path
rather than rewriting it into a less-tested NM-native form. A second USB
WiFi adapter is the only fully-supported way to do reliable AP+client.

### Audio + display

sbitx opens the WM8731 codec directly via ALSA, plus the `snd-aloop`
virtual cards (for WSJT-X). The Pixel desktop pulls in pipewire/
pulseaudio, which would grab the codec; `02-zbitx-os` masks
`pipewire`/`pipewire-pulse`/`wireplumber`/`pulseaudio` for all users and
sets `autospawn = no`. The desktop session is pinned to **X11/openbox**
(`do_wayland W1`) because sbitx is a GTK3/X11 app launched via
`/etc/xdg/autostart`, which the openbox session honors and the default
labwc/Wayland session does not.

### Remote access: VNC over WiFi

The radio can be driven remotely over WiFi. `02-zbitx-os` enables
**RealVNC in service mode** (`vncserver-x11-serviced.service`), which
mirrors the live X11 `:0` autologin session — so a VNC client sees the
same sBitx screen the physical display shows, not a separate virtual
desktop. `realvnc-vnc-server` already ships in the stock Desktop stage
(stage4's `00-packages-nr`), so nothing is added to `00-packages`; the
stage only enables the unit.

This is what `raspi-config nonint do_vnc 0` does, but the recipe enables
the unit directly: `do_vnc` also `systemctl start`s it, which fails in
the build chroot (no running PID 1). Enabling the unit is enough — at
boot it attaches to the `:0` session brought up by desktop autologin.
**It depends on the X11/openbox pin** (`do_wayland W1`, see "Audio +
display"): RealVNC service mode captures an X display, and the default
labwc/Wayland session would have none.

Reachability and auth:

- **Port 5900**, reachable over both `wlan0` (the client network) and the
  `zbitx` AP (`uap0`). The iptables rules only NAT-redirect port 80→8080;
  the filter table is default-ACCEPT, so 5900 is not blocked.
- **Authentication is RealVNC's default SystemAuth** — connect as user
  `pi` with the password the operator provisions via Raspberry Pi Imager
  (`firstrun.sh`). No VNC credential is baked, matching the image's
  "ship no default password" posture. Corollary: an image flashed with
  *no* Imager password leaves `pi` locked, so VNC accepts no login until
  a password is set.

The reference image, by contrast, ships `realvnc-vnc-server` installed
but **never enabled** (no `multi-user.target.wants` symlink, empty
`/root/.vnc/config.d`, no passwd) — so its VNC does not listen on a
booted radio. This build deliberately enables it.

Guarded by `03-zbitx-tests/files/87-vnc-enabled.sh` (asserts the server
is present and the unit is enabled).

### `docs/` and `vendor/`

- `bookworm-patches.md` — divergences from upstream zbitxv2 (still
  applies; the patches are in `build-sbitx.sh`).
- `vendor/pi-gen` — submodule, pinned to the `bookworm-arm64` branch
  (that branch hardcodes `ARCH=arm64`; the `bookworm` branch is armhf).
- `vendor/sbitx` — submodule, pinned zbitxv2 SHA. Bump explicitly.

## Tier-1 boot validation: systemd-nspawn

After the image build succeeds, CI boots the final (`stage-zbitx`)
rootfs as a systemd-nspawn container and confirms PID 1 reaches
`multi-user.target` within 90 seconds. This catches dynamic failures the
static in-chroot tests can't see: service ordering, D-Bus startup,
broken user/shell setup, and similar.

Limits: nspawn shares the host kernel, so kernel module loading
(`snd-aloop`, dtoverlays) and hardware-touching code (I2C, GPIO, WM8731
audio, the `wlan0`/`uap0` AP) are not exercised. `uap0.service`/`hostapd`/
`dnsmasq` self-skip or fail harmlessly with no `wlan0` present, which
does not block `multi-user.target`. The boot log is uploaded as the
`nspawn-log` artifact and tailed into the run summary.

## What about QEMU?

A previous iteration attempted a Tier-2 QEMU boot test against the
produced SD image. QEMU's `raspi3b`/`raspi4b` machines are too
incomplete to reliably boot an off-the-shelf Pi OS image to a
serial-visible login prompt (Pi firmware / GPU init, serial-console
setup). After several iterations it was removed. Real-hardware flash is
the path that genuinely works for "does it boot?", and lives outside CI.

## What's NOT tested at build time

Anything requiring real GPIO/I2C hardware, the WM8731 codec, the actual
radio path, the kernel / Pi firmware boot path, or the concurrent
AP+client RF behavior. Those are real-hardware-only — flash and validate
per the checklist in `docs/bookworm-patches.md`.

## `.github/workflows/build.yml`

GHA workflow on `ubuntu-24.04-arm` (native arm64, no qemu needed).
Checks out submodules, installs pi-gen host deps + `syft` (for the
SBOM), builds via `scripts/pi-gen-build.sh`, runs the Tier-1 nspawn boot
test, and uploads the `.img.xz`, the SBOM/`.info`, the build log, and the
nspawn log as artifacts. pi-gen keeps a full rootfs copy per stage, so a
Desktop build is disk-heavy; the workflow frees space first and may need
a larger volume if it grows.
