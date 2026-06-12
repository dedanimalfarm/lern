#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS dev_db;"
sudo -u postgres psql -c "DROP ROLE IF EXISTS alice;"
echo "Cleaned up module 02"
