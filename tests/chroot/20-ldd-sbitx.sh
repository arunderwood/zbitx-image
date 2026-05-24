#!/bin/sh
# Assert the sbitx binary's dynamic linker can resolve every dependency.
set -eu

BIN=/home/pi/sbitx/sbitx
if [ ! -x "$BIN" ]; then
    echo "FAIL: $BIN missing or not executable" >&2
    exit 1
fi

# `ldd` complains on cross-arch; we're running this in-chroot so native.
if ldd "$BIN" | grep -q 'not found'; then
    echo "FAIL: unresolved shared libraries:" >&2
    ldd "$BIN" | grep 'not found' >&2
    exit 1
fi

# Sanity check key libs are linked
for lib in libwiringPi libasound libfftw3 libfftw3f libsqlite3 libgtk-3 libncurses; do
    if ! ldd "$BIN" | grep -q "$lib"; then
        echo "FAIL: $BIN not linked against $lib" >&2
        exit 1
    fi
done

echo "OK: $BIN links cleanly"
