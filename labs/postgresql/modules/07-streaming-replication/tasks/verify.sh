#!/bin/bash
if sudo -u postgres psql -p 5433 -t -c "SELECT pg_is_in_recovery();" | grep -q "t"; then
    echo "PASS: Instance on port 5433 is in recovery mode (Replica)"
else
    echo "FAIL: Replica on port 5433 not found or not in recovery"
fi
