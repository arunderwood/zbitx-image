#!/bin/sh
# Sanity-check /etc/iptables/rules.v4 and rules.v6 structurally. We can't
# actually `iptables-restore --test` inside the mmdebstrap chroot because the
# kernel namespace lacks CAP_NET_ADMIN — even as root in the chroot,
# iptables refuses with "Permission denied (you must be root)".
#
# These files are consumed by iptables-persistent at boot on real hardware.
# Validate structure here; real-hw boot will exercise them for real.
set -eu

CONF=/etc/iptables/rules.v4
if [ ! -r "$CONF" ]; then
    echo "FAIL: $CONF missing or unreadable" >&2
    exit 1
fi

# Required table sections
for section in '\*nat' '\*filter'; do
    if ! grep -qE "^${section}" "$CONF"; then
        echo "FAIL: missing section ${section} in $CONF" >&2
        exit 1
    fi
done

# Required COMMIT after each table
commits=$(grep -c '^COMMIT$' "$CONF")
if [ "$commits" -lt 2 ]; then
    echo "FAIL: expected at least 2 COMMIT lines, found $commits" >&2
    exit 1
fi

# Required NAT rule: port 80 → 8080 redirect (this is the whole point
# of having iptables on the image — sbitx's mongoose server listens
# on :8080 and we want :80 to reach it).
if ! grep -qE 'dport 80.*REDIRECT.*to-ports 8080' "$CONF"; then
    echo "FAIL: missing 80→8080 REDIRECT rule in $CONF" >&2
    grep -i redirect "$CONF" >&2 || true
    exit 1
fi

# ---- IPv6: rules.v6 must also be present and structurally valid. Without it
# the netfilter-persistent 25-ip6tables plugin fails at boot ("cannot open
# /etc/iptables/rules.v6" → "IPv6 rules failed test load. New rules NOT
# loaded"). sbitx is IPv4-only, so a bare default-accept *filter table is all
# that's required — but the file MUST exist and parse.
CONF6=/etc/iptables/rules.v6
if [ ! -r "$CONF6" ]; then
    echo "FAIL: $CONF6 missing or unreadable" >&2
    exit 1
fi
if ! grep -qE '^\*filter' "$CONF6"; then
    echo "FAIL: missing *filter section in $CONF6" >&2
    exit 1
fi
if ! grep -q '^COMMIT$' "$CONF6"; then
    echo "FAIL: missing COMMIT in $CONF6" >&2
    exit 1
fi

echo "OK: $CONF + $CONF6 structurally valid (real iptables test deferred to first boot)"
