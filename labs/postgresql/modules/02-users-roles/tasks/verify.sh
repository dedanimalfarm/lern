#!/bin/bash
if PGPASSWORD=alice123 psql -h 127.0.0.1 -U alice -d dev_db -c "SELECT * FROM secret_data;" >/dev/null 2>&1; then
    echo "PASS: alice can read data"
else
    echo "FAIL: alice cannot read data (Check USAGE ON SCHEMA)"
fi
