#!/bin/bash
set -e

echo "Downloading Northwind for PostgreSQL..."
wget -qO northwind.sql https://raw.githubusercontent.com/yugabyte/yugabyte-db/master/sample/northwind_ddl.sql
wget -qO northwind_data.sql https://raw.githubusercontent.com/yugabyte/yugabyte-db/master/sample/northwind_data.sql

echo "Creating database 'northwind'..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS northwind;"
sudo -u postgres psql -c "CREATE DATABASE northwind;"

echo "Importing schema and data..."
sudo -u postgres psql -d northwind -f northwind.sql > /dev/null
sudo -u postgres psql -d northwind -f northwind_data.sql > /dev/null

rm northwind.sql northwind_data.sql
echo "Success! Database 'northwind' is ready."
