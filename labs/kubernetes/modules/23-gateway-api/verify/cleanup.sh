#!/usr/bin/env bash
set -euo pipefail

kubectl delete namespace lab-gateway --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
echo "cleanup: Envoy Gateway и GatewayClass eg не тронуты — это persistent-аддон стенда (scripts/bootstrap/11-install-gateway-api.sh)"
echo "cleanup: готово"
