#!/bin/sh
# Assert the desktop audio stack will not start under the pi user session.
#
# sbitx requires exclusive ALSA access to the WM8731 codec (hw:0,0) and
# the snd-aloop virtual cards. raspberrypi-ui-mods pulls in pipewire,
# pipewire-pulse, wireplumber, and pulseaudio transitively via Recommends
# on the lxplug-volumepulse / wfplug-volumepulse panel plugins; their
# user units are socket-activated and would otherwise spawn the moment
# any libpulse client hits the socket, grabbing the ALSA device.
#
# os-config.sh masks them via `systemctl --global mask ...`, which writes
# /etc/systemd/user/<unit> -> /dev/null. Verify each unit is masked using
# the system-instance --global view (per-user instances don't exist in a
# chroot).
set -eu

UNITS="pipewire.socket pipewire-pulse.socket wireplumber.service pulseaudio.socket pulseaudio.service"

failed=""
for unit in $UNITS; do
    # If the unit file isn't installed at all, that's also fine — nothing
    # to start. Skip silently in that case (e.g. wireplumber absent on a
    # leaner package set).
    if ! systemctl --global cat "$unit" >/dev/null 2>&1; then
        continue
    fi

    state=$(systemctl --global is-enabled "$unit" 2>/dev/null || true)
    if [ "$state" != "masked" ]; then
        echo "FAIL: user unit '$unit' is '$state' (expected 'masked')" >&2
        failed="$failed $unit"
    fi
done

if [ -n "$failed" ]; then
    echo "FAIL: audio-stack units not masked:$failed" >&2
    echo "--- /etc/systemd/user/ links ---" >&2
    ls -la /etc/systemd/user/ 2>/dev/null | head -20 >&2 || true
    exit 1
fi

echo "OK: desktop audio stack (pipewire/pulseaudio/wireplumber) is masked"
