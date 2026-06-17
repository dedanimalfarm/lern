#!/usr/bin/env bash
set -euo pipefail

docker compose -f lab/compose.yaml up -d >/dev/null
trap 'docker compose -f lab/compose.yaml down -v --remove-orphans >/dev/null 2>&1 || true' EXIT

# Wait for cadvisor/metrics to be ready
for i in {1..15}; do
  if curl -fsS http://localhost:8086/metrics >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS http://localhost:8085 >/dev/null
curl -fsS http://localhost:8086/metrics >/dev/null
curl -fsS http://localhost:9090/-/healthy >/dev/null

echo 'verify: ok'
