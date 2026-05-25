#!/bin/sh
# Apply Bookworm-port patches and build the zbitxv2 binary.
# Runs inside the chroot. Expects /home/pi/sbitx/ to contain the source tree.
set -eux

cd /home/pi/sbitx

# ---- Patch setup-ap.sh to skip the archive.debian.org rewrite ----
# (lines 42-51 force an EOL-Buster repo; harmful on Bookworm).
# Strategy: comment the apt-sources rewrite block. Survives minor edits to
# the script by anchoring on a unique sentinel line.
if grep -q 'archive.debian.org' setup-ap.sh; then
    sed -i.bak \
        '/# Patch sources.list/,/^fi$/ s/^/# bookworm-port: /' \
        setup-ap.sh
fi

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

# ---- Seed hw_settings.ini with the v2 default, no `hw=` line ----
# Runtime auto-detect at sbitx.c:1411-1416 picks the right HW version.
# Users can override with `hw=4` for legacy zbitx v1 hardware.
cp data/default_hw_settings.ini data/hw_settings.ini
sed -i '/^hw=/d' data/hw_settings.ini

# ---- Quick sanity: did the binary link? ----
if [ ! -x ./sbitx ]; then
    echo "ERROR: ./sbitx binary missing after build" >&2
    exit 1
fi
file ./sbitx | grep -q ELF
