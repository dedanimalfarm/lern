#!/bin/bash
if PGPASSWORD=123 psql -h 127.0.0.1 -U postgres -c "SELECT 1" >/dev/null 2>&1; then
    echo "PASS: Authentication successful over TCP/IP"
else
    echo "FAIL: Cannot connect over TCP/IP"
fi
