#!/bin/sh
# Assert /home/pi/sbitx/data/hw_settings.ini is seeded with the v1
# defaults that build-sbitx.sh is supposed to drop in:
#   - hw=4 explicitly set (auto-detect at sbitx.c:1411 cannot reach
#     SBITX_V4, so this MUST be present for any zBitx hardware)
#   - bfo_freq=40035000 (v1 BFO calibration)
#   - 40m [tx_band] has both f_start AND f_stop (upstream typo patch
#     in build-sbitx.sh — without f_stop, set_tx_power_levels falls
#     through and 40m TX scaling is wrong)
#
# Regression guard for the discussion at:
#   docs/architecture.md + README.md "Hardware variant"
set -eu

INI=/home/pi/sbitx/data/hw_settings.ini

if [ ! -f "$INI" ]; then
    echo "FAIL: $INI missing" >&2
    exit 1
fi

if ! grep -qx 'hw=4' "$INI"; then
    echo "FAIL: $INI missing 'hw=4' line" >&2
    echo "(zBitx hardware needs SBITX_V4 code path; auto-detect cannot reach it)" >&2
    echo "--- $INI ---" >&2
    cat "$INI" >&2
    exit 1
fi

if ! grep -qx 'bfo_freq=40035000' "$INI"; then
    echo "FAIL: $INI missing expected v1 BFO 'bfo_freq=40035000'" >&2
    grep '^bfo_freq=' "$INI" >&2 || true
    exit 1
fi

# Verify the 40m typo patch landed: f_start=7000000 must be followed
# by f_stop=7300000 before the next scale= line.
if ! awk '
    /^f_start=7000000$/ { in40m=1; next }
    in40m && /^f_stop=7300000$/ { ok=1; in40m=0; next }
    in40m && /^scale=/ { exit 1 }
    END { exit !ok }
' "$INI"; then
    echo "FAIL: $INI 40m [tx_band] missing f_stop=7300000 after f_start=7000000" >&2
    echo "(typo patch in stage-zbitx/01-zbitx-app/files/build-sbitx.sh did not apply)" >&2
    exit 1
fi

echo "OK: $INI has hw=4, v1 BFO, and 40m f_stop typo patched"
