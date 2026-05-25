#!/bin/sh
# Assert FFTW3 (installed under /usr/local/lib by ./configure && make
# install) is reachable via the runtime linker. Without an entry in
# ld.so.cache or a matching ld.so.conf.d snippet, the sbitx binary
# would compile + link fine at build time (RPATH or build-time
# linker search) but fail to start at runtime with "cannot open
# shared object file: No such file or directory".
set -eu

if ! ldconfig -p 2>/dev/null | grep -q '^[[:space:]]*libfftw3\.so\.3'; then
    echo "FAIL: libfftw3.so.3 not in ld.so.cache" >&2
    echo "--- ldconfig -p (head) ---" >&2
    ldconfig -p 2>/dev/null | head -5 >&2 || true
    echo "--- /etc/ld.so.conf.d ---" >&2
    ls -la /etc/ld.so.conf.d/ >&2 || true
    exit 1
fi

if ! ldconfig -p 2>/dev/null | grep -q '^[[:space:]]*libfftw3f\.so\.3'; then
    echo "FAIL: libfftw3f.so.3 not in ld.so.cache" >&2
    exit 1
fi

echo "OK: libfftw3 + libfftw3f reachable via ld.so.cache"
