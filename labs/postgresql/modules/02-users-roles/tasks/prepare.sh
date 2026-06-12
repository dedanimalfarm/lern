#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS dev_db;"
sudo -u postgres psql -c "CREATE DATABASE dev_db;"
sudo -u postgres psql -d dev_db -c "CREATE ROLE alice WITH LOGIN PASSWORD 'alice123';"
sudo -u postgres psql -d dev_db -c "CREATE TABLE secret_data(id int);"
sudo -u postgres psql -d dev_db -c "REVOKE ALL ON SCHEMA public FROM PUBLIC;"
sudo -u postgres psql -d dev_db -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO alice;"
echo "Prepared scenario for module 02"
