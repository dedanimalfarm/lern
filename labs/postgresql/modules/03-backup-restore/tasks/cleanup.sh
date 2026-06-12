#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS backup_db;"
rm -f /tmp/target.dump /tmp/backup.sql /tmp/backup.dump
echo "Cleaned up module 03"
