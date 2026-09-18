#!/usr/bin/env bash
set -euo pipefail
kubectl -n lab set env deploy/frontend OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
kubectl -n lab rollout status deploy/frontend --timeout=300s
