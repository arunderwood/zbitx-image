#!/bin/sh
# Assert sbitx logbook DB exists and has the expected schema.
set -eu

DB=/home/pi/sbitx/data/sbitx.db
if [ ! -f "$DB" ]; then
    echo "FAIL: $DB missing" >&2
    exit 1
fi

# Tables the schema in data/create_db.sql defines (verify by name).
for t in logbook; do
    if ! sqlite3 "$DB" ".tables" | tr -s ' ' '\n' | grep -qx "$t"; then
        echo "FAIL: table '$t' missing from $DB" >&2
        sqlite3 "$DB" ".tables" >&2
        exit 1
    fi
done

echo "OK: $DB schema present"
