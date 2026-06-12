#!/bin/bash
mkdir -p monitoring
cat << 'EOF' > monitoring/docker-compose.yaml
version: "3"
services:
  exporter:
    image: prometheuscommunity/postgres-exporter
    environment:
      DATA_SOURCE_NAME: "postgresql://postgres:password@host.docker.internal:5432/postgres?sslmode=disable"
    ports:
      - "9187:9187"
    extra_hosts:
      - "host.docker.internal:host-gateway"
EOF
echo "Prepared exporter docker-compose. Run 'cd monitoring && docker compose up -d' if Docker is installed."
