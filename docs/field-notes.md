# zBitx field notes

Curated knowledge from the [BITX20 groups.io list](https://groups.io/g/BITX20)
and other owner reports — hardware fixes, software tips, operating gotchas, and
anything else worth not losing in the mailing-list archive. These are notes
**about owning and running a zBitx**, distinct from this image's build recipe.

> **Caveat.** Entries come from individual operators and have not been verified
> by the maintainer or against a schematic/firmware revision here. Confirm
> details against your own hardware, and treat reported results as one person's
> bench experience.

---

## Pi-CPU noise on the v1 speaker (input-cap upgrade on U6 7805)

**Applies to:** zBitx **v1** hardware.

**Symptom.** A noise on the speaker that tracks Raspberry Pi CPU activity —
audible as a tick/buzz on every FFT cycle of the software. The noise is **not**
on the audio path: earphones are clean, so it isn't coupled through the audio
stages. It rides in on the **9 V main power line**, which also feeds the LM386
audio amplifier supply.

**Cause.** The Raspberry Pi is fed from **U6 (a 7805 regulator)**, whose input
on the schematic has only **47 µF** of bulk capacitance. At 200 Hz, 47 µF is
about **16 Ω** — roughly double the speaker impedance — so it's a poor bypass
for audio-frequency current drawn by the Pi, and that current modulates the
shared 9 V rail.

**Fix.** Solder a larger electrolytic across **Vi → GND of U6 (the 7805
input)**. The contributor used a **470 µF** cap (≈ **1.6 Ω** at 200 Hz, ~10×
lower impedance), which substantially reduced the speaker noise. A larger value
would help further; 470 µF was simply the biggest part on hand.

**Source:** Lluís —
[groups.io/g/BITX20, topic 119681185](https://groups.io/g/BITX20/topic/annoying_pi_cpu_noise_to/119681185).

---

## Related projects

### drexjj/zbitx — enhanced 32-bit sBitx app + image

[github.com/drexjj/zbitx](https://github.com/drexjj/zbitx), by JJ (W9JES) and
Juan (WP3DN). An alternative, enhanced fork of Farhan's (VU2ESE) sBitx
application plus a ready-to-flash OS image, with overlapping goals to this
project (a better out-of-box zBitx experience).

**How it overlaps / differs from this build:**

- **Base & arch.** drexjj ships a **32-bit Raspberry Pi OS** image tuned for
  the **Pi Zero 2 W**. This project targets **arm64 Bookworm** built from
  pi-gen (`stage-zbitx/`). So their image and binaries are not interchangeable
  with ours.
- **App.** drexjj forks and modifies the **sBitx C application** itself
  (front-panel UF2 firmware included). This project currently builds the
  upstream app largely unmodified and focuses on the **image/recipe** around
  it.
- **Distribution.** They distribute a prebuilt image (32 GB SD or USB, via
  Etcher / Pi Imager) with install/upgrade, network-config, and backup/restore
  scripts plus bundled ham utilities. This project distributes a reproducible
  **build recipe** that produces the image.
- **Status (as of this note).** Beta; they flag **CW as not fully working** in
  the beta build.

**Why it's worth tracking:** their app-level enhancements and bundled-utility
choices are a useful reference point for the
[reference-parity inventory](reference-parity-inventory.md) — a second
data point (alongside the maintainer's official image) for what a "complete"
zBitx software load looks like.
