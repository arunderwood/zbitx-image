# Reference-image feature-parity inventory

What the maintainer's official **zbitxv2 reference image** ships that this
pi-gen build (`stage-zbitx/`) does **not** yet implement, with an
implementation plan for each.

**Method.** The reference image was loop-mounted read-only via
[`scripts/inspect-reference-image.sh`](../scripts/inspect-reference-image.sh)
(see [docs/inspecting-the-reference-image.md](inspecting-the-reference-image.md))
and diffed against `stage-zbitx`: enabled systemd units, autostart entries,
`/home/pi` scripts, `Desktop/` launchers, ALSA config, and the installed
package set. Reference base is **Raspbian 10 (buster, 32-bit)**; this build
targets **arm64 Bookworm**, so everything below is *intent to translate*, not
files to copy verbatim. Reviewed 2026-06-14.

> **Decision (maintainer):** adopt the reference's **terminal launcher**
> (`start.sh` in a terminal window) rather than this build's current headless
> bare-binary autostart. See §2.1.

---

## The single most important integration fact

**sBitx is its own Hamlib NET rigctld server.** `hamlib.c` in the app binds
`127.0.0.1:4532` and answers rigctl `dump_state` / get-freq / set-freq / PTT
commands. Every "companion" digital-mode app controls the radio by connecting
to **that** server, not via a serial CAT line and not via the `hamlib`
package:

- **WSJT-X** → `Rig=Hamlib NET rigctl`, `CATNetworkPort=127.0.0.1` (:4532),
  `PTTMethod=CAT`.
- **fldigi** → `HAMRIGDEVICE=127.0.0.1:4532` (Hamlib NET).

Audio between those apps and sBitx flows over the **`snd-aloop`** virtual
cards this build already provisions (cards 1/2/3). So the snd-aloop wiring
that exists today has, currently, **no consumer installed** — WSJT-X is the
intended consumer and is not yet in the package set.

Audio device mapping the companions expect (from `wsjtx_notes.txt`):

| Direction | ALSA device                          | Channel |
| --------- | ------------------------------------ | ------- |
| Input     | `plughw:CARD=Loopback,DEV=1`         | Left    |
| Output    | `plughw:CARD=Loopback1,DEV=0`        | Both    |

---

## 1. Custom maintainer programs & scripts (highest priority — the "zbitx delta")

These are the maintainer's own code, present nowhere upstream-generic. Confidence that each is a deliberate product feature: **high**.

### 1.1 `zbitx-ap-manager.py`
- **What:** GTK3 GUI to start/stop the `zbitx` AP, change the WPA passphrase
  in `/etc/hostapd/hostapd.conf` (via `sudo sed` + `systemctl restart
  hostapd`), and list connected stations (`iw dev uap0 station dump`).
- **Reference wiring:** lives at `/home/pi/zbitx-ap-manager.py`; launched from
  `Desktop/zbitx-ap.desktop` (`Exec=python3 /home/pi/zbitx-ap-manager.py`).
- **To implement:** ship the script (it's vendored in the submodule —
  [`vendor/sbitx/zbitx-ap-manager.py`](../vendor/sbitx/zbitx-ap-manager.py));
  add `python3-gi` + `python3-gi-cairo` to `00-packages` (verify whether the
  RPi OS Desktop base already pulls them); add the Desktop launcher; ensure
  the passwordless-sudo path for `pi` to `sed`/`systemctl restart hostapd`
  exists (a polkit rule or sudoers drop-in — the reference relied on the
  desktop user's sudo).

### 1.2 `bt-monitor.sh` + Bluetooth audio stack
- **What:** toggles Bluetooth monitoring of sBitx's **left** channel —
  `alsaloop -C plughw:1,1 -P bluetooth ...` — so the operator can hear receive
  audio on BT headphones.
- **Reference wiring:** `/home/pi/bt-monitor.sh`; toggled from
  `Desktop/bt-monitor.desktop`. Depends on:
  - `/etc/asound.conf` (system-wide) defining named PCMs `audioinjector`,
    `bluetooth` (a `type bluealsa` slave **with a hard-coded headset MAC**),
    and `bt_left` (a `type route` that folds L+R → the BT sink). **The MAC is
    personal and must not be copied** — needs a device-agnostic approach.
  - `bluez-alsa` daemon + `blueman` (BT pairing GUI), `blueman-applet`
    autostart, and `bluealsa.service` enabled.
  - `alsa-utils` for `alsaloop` (stock on RPi OS).
- **To implement:** ship `bt-monitor.sh` + launcher; add the BT audio packages
  (**packaging changed — see §3**); lay down an `/etc/asound.conf` whose
  `bluetooth` PCM does **not** hard-code a MAC (e.g. resolve the connected
  A2DP device at runtime, or document a one-line pairing step). Confidence the
  *feature* is intended: high; confidence the exact `asound.conf` is portable:
  low.

### 1.3 `start.sh` terminal launcher  *(IMPLEMENTED 2026-06-14)*
- **What:** `sudo fuser -vu /dev/snd/*` (diagnostic only — lists holders of the
  sound devices, does NOT free the codec), `cd sbitx`, `./sbitx`, then `bash` +
  `read` so a crash leaves a visible console the operator can restart from.
- **Reference wiring:** `~/.config/autostart/sbitx.desktop` →
  `Exec=x-terminal-emulator -e "/home/pi/sbitx/start.sh"`.
- **Implemented as:** instead of the fragile upstream `start.sh` (no shebang,
  relative `cd`), this build ships a controlled wrapper
  `/usr/local/bin/sbitx-launch` (overlay; chmod 0755 in 02-zbitx-os/00-run.sh)
  and points `/etc/xdg/autostart/sBitx.desktop` at
  `Exec=x-terminal-emulator -e /usr/local/bin/sbitx-launch`. Crash visibility +
  restart-shell preserved; `|| true` ensures sudo/fuser can never hang boot.
  Guarded by test `03-zbitx-tests/files/85-terminal-launcher.sh` (also asserts
  `x-terminal-emulator` is present — `lxterminal` is stock on the Desktop base,
  so not added to `00-packages`).

---

## 2. System-integration deltas (smaller, mostly config)

| # | Artifact | Reference | This build | To implement | Confidence |
| - | -------- | --------- | ---------- | ------------ | ---------- |
| 2.1 | **Launch model** | terminal + `start.sh` (§1.3) | ~~headless bare binary~~ → terminal via `/usr/local/bin/sbitx-launch` | **DONE** (§1.3) | — |
| 2.2 | **`~/.asoundrc`** | user ALSA default: asym duplex on card 0 | absent | seed `~/.asoundrc` (sBitx + companions assume a sane card-0 default) | med |
| 2.3 | **`/etc/asound.conf`** | named PCMs (`audioinjector`, `bluetooth`, `bt_left`) | absent | needed by `bt-monitor.sh`; de-personalise the BT MAC (§1.2) | med |
| 2.4 | **Hostname `sbitx`** + `/etc/hosts` | `127.0.1.1 sbitx` | already set via `TARGET_HOSTNAME` (pi-gen.config) | **DONE** (base pi-gen) | — |
| 2.5 | ~~**`sbitx.service`**~~ | unit exists but **not enabled** | n/a | **WON'T DO** — broken artifact: `main()` treats `argv[1]` as the ALSA device ([sbitx_gtk.c:5135-5138]), so `sbitx -boot` opens a device named `-boot` and fails. That's why the reference disables it. | — |
| 2.6 | **`hostapd.service.d/restart.conf`** | `Restart=on-failure, RestartSec=5` | ~~absent~~ → shipped | **DONE** — AP self-heals; test `86-hostapd-restart.sh` | — |
| 2.7 | ~~**`~/.sbitx/` seeds**~~ | `bands.ini`, `band_stack.ini`, `user_settings.ini` (2022-era) | n/a | **WON'T DO** — obsolete path. Current sBitx reads `$HOME/sbitx/data/user_settings.ini`, self-defaults + falls back to shipped `data/default_settings.ini` if absent ([sbitx_gtk.c:5160-5183]). | — |
| 2.8 | **Desktop launchers + menu** | `Desktop/{sBitx,zbitx-ap,bt-monitor,Electronics,Hamradio}.desktop` + an alacarte menu entry | none | ship the launchers; the `sBitx.desktop` Link points at an alacarte-generated entry — recreate as a normal `.desktop` instead | med |

---

## 3. Companion app suite (full documentation, per request)

The reference is effectively a **ham-radio desktop appliance**; this build is
**sBitx-only**. Each app below, with how it's configured, its purpose +
confidence it's a deliberate feature, and whether it's still the
Bookworm/Trixie standard.

| App | Reference config | Purpose for the image | Confidence it's intended | Bookworm/Trixie standard? | Recommendation |
| --- | ---------------- | --------------------- | ------------------------ | ------------------------- | -------------- |
| **WSJT-X** | `~/.config/WSJT-X.ini`: `Rig=Hamlib NET rigctl`, CAT→127.0.0.1:4532, `PTTMethod=CAT`, audio in `Loopback,DEV=1`/Left, out `Loopback1,DEV=0`/Both, `Mode=FT8`. Reference hand-installed armhf **2.5.4** (buster hack, `wsjtx_notes.txt`). | FT8/FT4/WSPR digital modes driving sBitx via its rigctld server + snd-aloop. **This is the consumer the existing snd-aloop wiring was built for.** | **High** | **Yes.** `wsjtx` 2.6.x in bookworm, 2.7.0 in trixie, arm64 available; the armhf-package hack is obsolete — just `apt install wsjtx`. (`wsjtx-improved` 2.8 also in trixie.) | **Install.** Highest-value add; pre-seed the CAT/audio `WSJT-X.ini` so it talks to sBitx out of the box. |
| **fldigi** | `~/.fldigi/fldigi_def.xml`: `HAMRIGDEVICE=127.0.0.1:4532` (Hamlib NET). In this snapshot `CHKUSEHAMLIBIS=0` (not actively on) but pointed at sBitx. | All-mode soundcard digital (RTTY/PSK/Olivia/MFSK/CW) via sBitx's rigctld + snd-aloop. | **Medium-high** | **Yes**, still the standard all-mode soundcard app; packaged + maintained (W1HKJ). | **Install** if matching the digital workflow; pre-seed Hamlib-NET rig config. |
| **flrig** | `~/.flrig/flrig.prefs`: `xcvr_name:NONE` — **unconfigured/unused**. | Rig-control GUI companion to fldigi. Redundant here because **sBitx is its own rig server**. | **Low** | Packaged/maintained, but not needed. | **Skip** unless a specific need appears. |
| **hamlib** (`libhamlib-utils`/`rigctl`) | installed (`3.3`) but the apps use their built-in Hamlib NET clients. | rigctl/rigctld CLI. | **Low** | Current (4.5.x in trixie). | **Skip** — sBitx *is* the rig server; companions bundle their own hamlib. |
| **gpredict** | `~/.config/Gpredict/` present (qth, modules, satdata). | Satellite pass prediction / Doppler tracking. Standalone; not wired to sBitx. | **Low-medium** | Packaged; aging upstream but still the desktop standard. | **Optional** — hobby extra, defer. |
| **audacity** | `~/.audacity-data/audacity.cfg` (default-ish). | Audio recording/editing. Standalone. | **Low** | Standard; bookworm 3.x (reference's 2.2.2 is buster-era). | **Optional** — not radio-critical. |
| **claws-mail** | `~/.claws-mail/` (personal account — do not copy). | Email client. No radio integration found. | **Low** | Maintained/packaged. | **Skip** — likely desktop leftover, not a radio feature. |
| **Bluetooth audio** (`bluez-alsa` + `blueman`) | `bluealsa.service` hand-rolled `ExecStart=/usr/bin/bluealsa -p a2dp-source -p a2dp-sink`; `blueman-applet` autostart. | A2DP so sBitx RX audio can be monitored on BT headphones (drives §1.2). | **Medium-high** (it's why `bt-monitor.sh` exists) | **Packaging changed** — see note. | **Install via the packaged unit**, not the hand-rolled service. |

> **`bluez-alsa` packaging delta (important).** Buster shipped a `bluealsa`
> 0.13 binary; the reference's hand-written `bluealsa.service` with
> `ExecStart=/usr/bin/bluealsa …` **will not port cleanly**. Bookworm/Trixie
> ship the package as **`bluez-alsa-utils`** (bookworm 4.0.0, trixie 4.3.1)
> with its own packaged service. In the newer (trixie) version the daemon was
> **renamed `bluealsa` → `bluealsad`**, config → `org.bluealsa.conf`, CLI →
> `bluealsactl`, with no backward compat. So: depend on `bluez-alsa-utils`,
> use its shipped unit, and update the `type bluealsa` PCM syntax in
> `/etc/asound.conf` to the installed version. Also weigh PipeWire
> interaction — this build masks PipeWire/PulseAudio for the codec, which
> affects BT audio routing.

---

## 4. Explicitly NOT to port (reference cruft, not features)

- Personal data: callsign/grid `vu2lch`/`Mk97fj` in settings, `.claws-mail`
  account, `.bash_history`, `.ssh`, `network-backup-*`, real BT headset MAC.
- Editor swap files (`*.swp`) committed into `data/` and `.sbitx/`.
- In-home source trees (`bluez-5.55/`, `WiringPi/`) — build artifacts; this
  build installs WiringPi from a pinned `.deb`.
- The contradictory `/etc/rc.local` block (`modprobe snd-aloop` + `fldigi` +
  `/home/pi/sbitx/sbitx`) — superseded here by `modules-load.d/snd-aloop.conf`
  + the desktop autostart. Do not replicate.
- Duplicate/legacy time sync (reference enables both `ntp` **and** `chrony`);
  this build uses Bookworm's `systemd-timesyncd` and sBitx's own `ntputil.c`.

---

## Suggested implementation order

1. **§2.4 hostname + §2.2 `~/.asoundrc`** — tiny, high-impact identity/audio.
2. ~~**§1.3 launch model** — adopt `start.sh` terminal launcher.~~ **DONE.**
3. **§1.1 AP manager** + **§2.8 Desktop launchers** — `python3-gi`, the
   script, sudo path.
4. **WSJT-X** (§3) — install + pre-seed `WSJT-X.ini`; finally gives the
   existing snd-aloop wiring a consumer.
5. **§1.2 BT monitor + Bluetooth stack** — the biggest porting effort
   (packaging + de-personalised `asound.conf`); do after the above.
6. **fldigi** (§3), then **§2.6 hostapd drop-in / §2.5 sbitx.service / §2.7
   `~/.sbitx` seeds** as polish.
7. **Optional/defer:** gpredict, audacity. **Skip:** flrig, hamlib,
   claws-mail.
