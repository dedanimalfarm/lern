#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS pool_db;"
sudo -u postgres psql -c "CREATE DATABASE pool_db;"
sudo -u postgres psql -c "DROP ROLE IF EXISTS pool_user;"
sudo -u postgres psql -c "CREATE ROLE pool_user WITH LOGIN PASSWORD 'pool_pass';"
sudo -u postgres psql -c "GRANT ALL ON DATABASE pool_db TO pool_user;"
echo "Prepared database pool_db and pool_user"
