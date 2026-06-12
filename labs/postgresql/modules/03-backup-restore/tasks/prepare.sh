#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS backup_db;"
sudo -u postgres psql -c "CREATE DATABASE backup_db;"
sudo -u postgres psql -d backup_db -c "CREATE TABLE users(id int);"
sudo -u postgres psql -d backup_db -c "CREATE TABLE logs(msg text);"
sudo -u postgres pg_dump -Fc backup_db -f /tmp/target.dump
sudo -u postgres psql -d backup_db -c "DROP TABLE users;"
echo "Prepared backup scenario in /tmp/target.dump"
