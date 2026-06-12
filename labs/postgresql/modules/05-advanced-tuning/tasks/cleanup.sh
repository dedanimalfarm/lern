#!/bin/bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS tune_db;"
# Restore defaults roughly
sed -i 's/^shared_buffers = 512MB/shared_buffers = 128MB/' /etc/postgresql/14/main/postgresql.conf
systemctl restart postgresql
echo "Cleaned up module 05"
