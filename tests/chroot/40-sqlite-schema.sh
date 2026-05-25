#!/bin/sh
# Assert sbitx logbook DB exists and has the schema from
# data/create_db.sql (logbook + messages + contacts tables, plus the
# logbook indexes that the GUI relies on for callsign lookup).
set -eu

DB=/home/pi/sbitx/data/sbitx.db
if [ ! -f "$DB" ]; then
    echo "FAIL: $DB missing" >&2
    exit 1
fi

TABLES=$(sqlite3 "$DB" ".tables" | tr -s ' ' '\n' | grep -v '^$' | sort)
for t in contacts logbook messages; do
    if ! echo "$TABLES" | grep -qx "$t"; then
        echo "FAIL: expected table '$t' missing from $DB" >&2
        echo "Tables present: $TABLES" >&2
        exit 1
    fi
done

# The two indexes (gridIx, callIx) are how the GUI does grid/callsign
# lookups; missing them would silently make the UI slow on first run.
INDEXES=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';" | sort)
for i in callIx gridIx; do
    if ! echo "$INDEXES" | grep -qx "$i"; then
        echo "FAIL: expected index '$i' missing from $DB" >&2
        echo "Indexes present: $INDEXES" >&2
        exit 1
    fi
done

echo "OK: $DB has expected tables + indexes"
