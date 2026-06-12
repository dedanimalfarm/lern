#!/bin/bash
sudo -u postgres psql -c "DROP ROLE IF EXISTS replicator;"
sudo -u postgres psql -c "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl_pass';"
echo "host replication replicator 127.0.0.1/32 scram-sha-256" >> /etc/postgresql/14/main/pg_hba.conf
systemctl reload postgresql
echo "Prepared replicator user"
