# Upstream tracking

Workarounds carried in this image that should ideally be fixed in upstream
projects (primarily the [sBitx firmware](https://github.com/afarhan/sbitx)).
Each entry records the workaround we ship here and the real fix that would let
us drop it.

| # | Area | Upstream fix wanted | Workaround here | Status |
|---|------|---------------------|-----------------|--------|
| 1 | sBitx audio | Make sBitx tolerate the WM8731 codec on any ALSA card index (and non-zero loopback indices) instead of hardcoding `hw:0` / `plughw:0,0`. | Disable HDMI audio (`dtoverlay=vc4-kms-v3d,noaudio`) so the codec keeps card 0. | Open |

---

## 1. sBitx hardcodes the audio codec as ALSA card 0

**Symptom (2026-06-14, first pi-gen image boot):** sBitx starts, prints
`Audio Output Device is: plughw:0,0`, then aborts with:

```
sbitx: simple.c:652: snd_mixer_selem_has_capture_switch: Assertion `elem' failed.
```

**Root cause:** sBitx hardcodes the codec as `hw:0` (`setup_audio_codec()` in
`sbitx.c` does `strcpy(audio_card, "hw:0")`) and `plughw:0,0` for the PCM
streams. Under the pi-gen image the `vc4-kms-v3d` overlay registers `vc4hdmi`
as an ALSA card, which takes index 0 and pushes the WM8731 (`audioinjectorpi`)
to a higher index. sBitx then queries WM8731 mixer controls (`Input Mux`,
`Master`, `Capture`, …) on the HDMI card; `snd_mixer_find_selem()` returns
`NULL`, and because sBitx's `if (elem)` guard in `sound_mixer()`
(`sbitx_sound.c`) is commented out, the `NULL` flows into
`snd_mixer_selem_has_capture_switch()` and the ALSA assertion aborts the
process.

**Real fix (upstream):** sBitx should locate the codec by card name (e.g.
search for `audioinjectorpi` / the WM8731) rather than assuming index 0, and
should defensively skip a mixer control when `snd_mixer_find_selem()` returns
`NULL` instead of passing it on. Restoring the commented-out `if (elem)` guard
alone would turn the hard crash into a degraded-but-running state.

**Workaround in this repo:** `stage-zbitx/02-zbitx-os/00-run.sh` appends
`,noaudio` to the `vc4-kms-v3d` overlay so HDMI registers no sound cards; with
`snd-aloop` pinned to indices 1,2,3, the WM8731 codec falls into the free
index 0, matching sBitx's expectation. Guarded by
`stage-zbitx/03-zbitx-tests/files/81-config-txt-overlays.sh`.

When sBitx no longer depends on card 0, drop the `,noaudio` workaround (and its
test assertion) so HDMI audio works again.
