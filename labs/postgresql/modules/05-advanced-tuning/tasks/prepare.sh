#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS tune_db;"
sudo -u postgres psql -c "CREATE DATABASE tune_db;"
sudo -u postgres pgbench -i -s 10 tune_db
echo "Prepared tune_db for pgbench"
