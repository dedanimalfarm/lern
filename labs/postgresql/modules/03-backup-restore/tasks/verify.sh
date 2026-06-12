#!/bin/bash
if sudo -u postgres psql -d backup_db -c "\dt" | grep -q "users"; then
    echo "PASS: Table users restored successfully"
else
    echo "FAIL: Table users not found"
fi
