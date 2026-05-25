#!/bin/sh
# Build FFTW3 double + single precision from source.
# Arg 1: tarball URL
# Arg 2: tarball SHA256 (or "skip")
set -eux

URL="$1"
SHA="$2"

cd /tmp
wget -q "$URL" -O fftw.tar.gz
if [ "$SHA" != "skip" ] && [ -n "$SHA" ]; then
    echo "$SHA  fftw.tar.gz" | sha256sum -c -
fi
tar -xzf fftw.tar.gz
SRCDIR=$(find . -maxdepth 1 -type d -name 'fftw-*' | head -n1)
cd "$SRCDIR"

# Double precision
./configure --quiet --enable-shared --disable-static
make -j"$(nproc)"
make install

# Float precision (same source, rebuild with --enable-float)
make clean
./configure --quiet --enable-float --enable-shared --disable-static
make -j"$(nproc)"
make install

ldconfig

cd /
rm -rf "/tmp/fftw.tar.gz" "/tmp/$SRCDIR"
