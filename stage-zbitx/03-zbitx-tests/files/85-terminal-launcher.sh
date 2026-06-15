#!/bin/sh
# Assert the sBitx terminal-launch path is wired: launcher exists + is
# executable, the autostart invokes it, and a terminal emulator is present.
# Regression guard for inventory §1.3 (docs/reference-parity-inventory.md):
# sBitx autostarts in a terminal so a crash stays visible and restartable.
set -eu
L=/usr/local/bin/sbitx-launch
D=/etc/xdg/autostart/sBitx.desktop

[ -x "$L" ] || { echo "FAIL: $L missing or not executable" >&2; exit 1; }
grep -q '^Exec=.*sbitx-launch' "$D" || {
    echo "FAIL: $D Exec does not invoke sbitx-launch" >&2
    grep '^Exec=' "$D" >&2 || true
    exit 1
}
command -v x-terminal-emulator >/dev/null 2>&1 || {
    echo "FAIL: no x-terminal-emulator on image (install a terminal, e.g. lxterminal)" >&2
    exit 1
}
echo "OK: sBitx terminal launcher wired (executable, autostart points at it, terminal present)"
