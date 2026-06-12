#!/bin/bash
mkdir -p cluster
cat << 'EOF' > cluster/docker-compose.yaml
version: "3"
# Псевдо-кластер для изучения. Требует реальных Docker образов Patroni.
# В рамках лабы скрипт prepare просто создает файл для ручного изучения.
services:
  etcd:
    image: bitnami/etcd:latest
    environment:
      - ALLOW_NONE_AUTHENTICATION=yes
  patroni1:
    image: zalando/spilo-14:latest
    environment:
      - ETCD_HOST=etcd:2379
EOF
echo "Prepared dummy docker-compose for review"
