#!/bin/bash
sudo systemctl stop pgbouncer
sudo -u postgres psql -c "DROP DATABASE IF EXISTS pool_db;"
sudo -u postgres psql -c "DROP ROLE IF EXISTS pool_user;"
echo "Cleaned up module 06"
