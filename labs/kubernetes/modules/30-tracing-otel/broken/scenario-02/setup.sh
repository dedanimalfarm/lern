#!/usr/bin/env bash
set -euo pipefail
kubectl -n lab set env deploy/frontend OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
kubectl -n lab rollout status deploy/frontend --timeout=300s
echo "инцидент применён: смотрите логи frontend и поиск в Tempo"
