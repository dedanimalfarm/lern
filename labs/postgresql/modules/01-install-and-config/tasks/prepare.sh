#!/bin/bash
echo "local   all             postgres                                peer" > /etc/postgresql/14/main/pg_hba.conf
echo "host    all             all             127.0.0.1/32            peer" >> /etc/postgresql/14/main/pg_hba.conf
echo "host    all             all             ::1/128                 peer" >> /etc/postgresql/14/main/pg_hba.conf
systemctl reload postgresql
echo "Prepared broken pg_hba.conf"
