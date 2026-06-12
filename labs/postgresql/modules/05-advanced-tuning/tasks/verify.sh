#!/bin/bash
# Check if shared_buffers is changed
VAL=$(sudo -u postgres psql -t -c "SHOW shared_buffers;" | tr -d ' ')
if [ "$VAL" = "512MB" ]; then
    echo "PASS: shared_buffers successfully tuned"
else
    echo "FAIL: shared_buffers is $VAL, expected 512MB"
fi
