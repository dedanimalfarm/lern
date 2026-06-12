#!/bin/bash
sudo systemctl stop postgresql@14-replica
sudo pg_dropcluster 14 replica
sed -i '/replicator/d' /etc/postgresql/14/main/pg_hba.conf
sudo -u postgres psql -c "SELECT pg_drop_replication_slot('replica_slot');"
systemctl reload postgresql
echo "Cleaned up module 07"
