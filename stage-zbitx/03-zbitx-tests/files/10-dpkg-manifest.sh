#!/bin/sh
# Verify packages that came from non-apt sources actually registered with
# dpkg. We deliberately do NOT check every apt-installed package — those
# all came through the stage package list, and a failure there
# would have aborted the build long before tests run. Checking them
# again here is fluff.
#
# What's worth checking:
#  - wiringpi: installed via `apt-get install /tmp/wiringpi.deb` from a
#    custom-downloaded .deb. If the SHA mismatched or the .deb was
#    malformed, `apt-get install /path` could in theory partially fail.
set -eu

if ! dpkg -s wiringpi >/dev/null 2>&1; then
    echo "FAIL: wiringpi package not registered with dpkg" >&2
    dpkg -l | grep -i wiringpi >&2 || true
    exit 1
fi

# Confirm the version is 3.x — the original drogon.net 2.x line is
# deprecated and we explicitly switched to the WiringPi/WiringPi fork.
ver=$(dpkg-query -W -f='${Version}' wiringpi 2>/dev/null)
case "$ver" in
    3.*) ;;
    *) echo "FAIL: wiringpi version is '$ver', expected 3.x" >&2; exit 1;;
esac

echo "OK: wiringpi $ver installed"
