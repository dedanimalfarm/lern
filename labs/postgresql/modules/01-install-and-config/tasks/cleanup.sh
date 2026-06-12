#!/bin/bash
# Revert to standard
echo "local   all             postgres                                peer" > /etc/postgresql/14/main/pg_hba.conf
echo "host    all             all             127.0.0.1/32            scram-sha-256" >> /etc/postgresql/14/main/pg_hba.conf
systemctl reload postgresql
echo "Cleaned up module 01"
