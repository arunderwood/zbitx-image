#!/bin/sh
# Apply Bookworm-port patches and build the zbitxv2 binary.
# Runs inside the chroot. Expects /home/pi/sbitx/ to contain the source tree.
set -eux

cd /home/pi/sbitx

# Note: upstream's setup-ap.sh contains an archive.debian.org apt-sources
# rewrite (lines 42-51) that's appropriate for EOL Buster and harmful on
# Bookworm. The recipe does NOT execute setup-ap.sh at build time — the
# AP stack is laid down declaratively via the stage-zbitx/02-zbitx-os
# overlay (etc/{hostapd,dnsmasq.d,systemd/system,iptables}). The script is shipped
# on the flashed image only for reference; an operator who runs it
# manually on a built image would hit the apt-sources problem, but that's
# a niche path we don't try to defend against. See docs/bookworm-patches.md
# section 3.

# ---- Drop ntp/ntpstat apt-installs from install.txt-derived steps ----
# Bookworm uses systemd-timesyncd; ntputil.c implements NTP directly so
# the packages were never load-bearing for the app.
# (install.txt is documentation only — not invoked at build time — so
# this is informational. Recipe declares deps in the layer manifest.)

# ---- Rebuild ft8_lib/libft8.a for the current arch ----
# The repo ships a prebuilt libft8.a that was compiled on a 32-bit
# armhf Pi. On Bookworm arm64 the linker rejects it with:
#   "ld: ft8_lib/libft8.a: error adding symbols: file in wrong format"
# Rebuild from source so the static library matches our target arch.
( cd ft8_lib && make clean && make all && make install )

# ---- Build the sbitx binary ----
./build sbitx

# ---- Initialize empty logbook DB ----
# build script already does this, but be defensive in case it was skipped.
if [ ! -f data/sbitx.db ]; then
    sqlite3 data/sbitx.db < data/create_db.sql
fi

# ---- Seed hw_settings.ini for zBitx v1 hardware (project default) ----
# The runtime auto-detect at sbitx.c:1411-1416 only chooses between
# SBITX_DE (0) and SBITX_V2 (1) by probing I2C address 0x8. It cannot
# pick SBITX_V4 (4), which is what BOTH zBitx v1 and v2 hardware
# require — the SWR bridge at 0x8 is present on zBitx too, so probe
# succeeds and the auto-detect falsely returns SBITX_V2. That code
# path then mishandles the relay sequencing, LPF management, and
# power-meter polling. So `hw=4` MUST be seeded explicitly here,
# not left to auto-detect.
#
# v1 is the current default — the project maintainer's hardware. v2
# users swap the active hw_settings.ini after first boot; see README
# "Flashing" section for the one-line cp + reboot.
#
# We patch one upstream typo: hw_settings_zbitxv1.ini's 40m [tx_band]
# is missing f_stop, so set_tx_power_levels() at sbitx.c:1067 will
# never match 40m and TX power scaling falls through to default for
# that band. Idempotent: skipped if upstream eventually fixes it.
cp data/hw_settings_zbitxv1.ini data/hw_settings.ini
grep -q '^f_stop=7300000' data/hw_settings.ini || \
    sed -i '/^f_start=7000000$/a f_stop=7300000' data/hw_settings.ini

# ---- Quick sanity: did the binary link? ----
# Just check existence + first 4 magic bytes for ELF. `file(1)` is not in
# the chroot's package set and adding it just for this check is silly.
if [ ! -x ./sbitx ]; then
    echo "ERROR: ./sbitx binary missing after build" >&2
    exit 1
fi
if ! head -c 4 ./sbitx | grep -q ELF; then
    echo "ERROR: ./sbitx does not start with ELF magic" >&2
    exit 1
fi

# ---- Drop the bundled FFTW wisdom files ----
# The upstream repo commits data/sbitx_wisdom*.wis files that were tuned
# on the original author's hardware. FFTW will re-evaluate plans against
# the target CPU on first launch anyway; better to start clean than ship
# stale wisdom that may be CPU-mismatched.
rm -f data/sbitx_wisdom.wis data/sbitx_wisdom_f.wis
