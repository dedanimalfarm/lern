#!/bin/bash
set -e

echo "Downloading PostgresPro Demo Database (demo-small)..."
wget -qO demo-small.zip https://edu.postgrespro.ru/demo-small.zip
unzip -q demo-small.zip -d ./
rm demo-small.zip

echo "Creating database 'demo' and importing data..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS demo;"
sudo -u postgres psql -c "CREATE DATABASE demo;"

# The SQL file name inside zip is usually demo-small.sql or demo.sql
# Let's find it dynamically
SQL_FILE=$(ls demo-small*.sql | head -n 1)

if [ -n "$SQL_FILE" ]; then
    sudo -u postgres psql -d demo -f "$SQL_FILE" > /dev/null
    rm "$SQL_FILE"
    echo "Success! Database 'demo' is ready."
else
    echo "SQL file not found after extraction."
fi
