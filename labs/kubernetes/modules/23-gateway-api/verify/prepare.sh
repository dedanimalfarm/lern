#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

if ! kubectl get gatewayclass eg >/dev/null 2>&1; then
  echo "GatewayClass 'eg' is missing. Installing Envoy Gateway..."
  bash "$ROOT_DIR/scripts/bootstrap/11-install-gateway-api.sh"
fi
