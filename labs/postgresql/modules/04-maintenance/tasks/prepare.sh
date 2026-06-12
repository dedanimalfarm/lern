#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS bench_db;"
sudo -u postgres psql -c "CREATE DATABASE bench_db;"
sudo -u postgres pgbench -i -s 10 bench_db
echo "Prepared bench_db with ~1M rows using pgbench"
