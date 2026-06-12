#!/bin/bash
if sudo -u postgres psql -d bench_db -c "\dt" | grep -q "pgbench_accounts"; then
    echo "PASS: bench_db exists and is ready"
else
    echo "FAIL: pgbench failed"
fi
