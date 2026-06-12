#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS bench_db;"
echo "Cleaned up module 04"
