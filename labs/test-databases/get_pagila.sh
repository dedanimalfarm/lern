#!/bin/bash
set -e

echo "Downloading Pagila (DVD Rental) schema and data..."
wget -qO pagila-schema.sql https://raw.githubusercontent.com/devrimgunduz/pagila/master/pagila-schema.sql
wget -qO pagila-data.sql https://raw.githubusercontent.com/devrimgunduz/pagila/master/pagila-data.sql

echo "Creating database 'pagila'..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS pagila;"
sudo -u postgres psql -c "CREATE DATABASE pagila;"

echo "Importing schema..."
sudo -u postgres psql -d pagila -f pagila-schema.sql > /dev/null

echo "Importing data..."
sudo -u postgres psql -d pagila -f pagila-data.sql > /dev/null

rm pagila-schema.sql pagila-data.sql
echo "Success! Database 'pagila' is ready."
