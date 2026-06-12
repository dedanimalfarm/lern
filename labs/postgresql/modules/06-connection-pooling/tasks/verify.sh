#!/bin/bash
if PGPASSWORD=pool_pass psql -h 127.0.0.1 -p 6432 -U pool_user -d pool_db -c "SELECT 1;" >/dev/null 2>&1; then
    echo "PASS: Successfully connected through PgBouncer on port 6432"
else
    echo "FAIL: Cannot connect to PgBouncer. Check /etc/pgbouncer/pgbouncer.ini and userlist.txt"
fi
